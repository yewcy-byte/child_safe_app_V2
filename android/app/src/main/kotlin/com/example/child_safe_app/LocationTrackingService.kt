package com.example.child_safe_app

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.SetOptions
import java.util.*

/**
 * Background service for continuous location tracking
 * Runs even when the app is closed
 */
class LocationTrackingService : Service() {

    private val TAG = "LocationTrackingService"
    private val NOTIFICATION_ID = 300
    private val CHANNEL_ID = "location_tracking_channel"
    
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationCallback: LocationCallback
    private lateinit var firestore: FirebaseFirestore
    private lateinit var auth: FirebaseAuth
    private var locationRefreshListener: ListenerRegistration? = null
    private var lastHandledRefreshAtMillis: Long = 0L
    
    private var lastLocation: Location? = null
    private var lastUploadTime: Long = 0
    
    // Upload interval (5 minutes)
    private val UPLOAD_INTERVAL_MS = 5 * 60 * 1000L
    
    // Minimum distance for update (100 meters)
    private val MIN_DISTANCE_METERS = 100f

    companion object {
        private var isRunning = false

        fun isServiceRunning(): Boolean = isRunning

        fun startService(context: Context) {
            val intent = Intent(context, LocationTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, LocationTrackingService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        
        firestore = FirebaseFirestore.getInstance()
        auth = FirebaseAuth.getInstance()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification())
        
        setupLocationCallback()
        startLocationUpdates()
        startLocationRefreshListener()
        
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service onStartCommand")
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy")
        
        stopLocationUpdates()
        stopLocationRefreshListener()
        isRunning = false
    }

    private fun startLocationRefreshListener() {
        val user = auth.currentUser
        if (user == null) {
            Log.w(TAG, "No user logged in, skipping location refresh listener")
            return
        }

        locationRefreshListener?.remove()
        locationRefreshListener = firestore
            .collection("users")
            .document(user.uid)
            .collection("systemRequests")
            .document("locationRefresh")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e(TAG, "Location refresh listener error: ${error.message}")
                    return@addSnapshotListener
                }

                val data = snapshot?.data ?: return@addSnapshotListener
                val requestedAtAny = data["requestedAt"]
                val requestedAt = when (requestedAtAny) {
                    is com.google.firebase.Timestamp -> requestedAtAny.toDate().time
                    else -> return@addSnapshotListener
                }

                if (requestedAt <= lastHandledRefreshAtMillis) {
                    return@addSnapshotListener
                }

                lastHandledRefreshAtMillis = requestedAt
                Log.d(TAG, "Received parent location refresh request")
                triggerImmediateLocationUpload()
            }
    }

    private fun stopLocationRefreshListener() {
        try {
            locationRefreshListener?.remove()
        } catch (_: Exception) {
        } finally {
            locationRefreshListener = null
        }
    }

    private fun triggerImmediateLocationUpload() {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Cannot refresh location: ACCESS_FINE_LOCATION not granted")
            return
        }

        try {
            fusedLocationClient.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
                .addOnSuccessListener { location ->
                    if (location != null) {
                        Log.d(TAG, "Immediate refresh location received")
                        handleLocationUpdate(location)
                    } else {
                        Log.w(TAG, "Immediate refresh returned null location; trying lastLocation")
                        fusedLocationClient.lastLocation
                            .addOnSuccessListener { last ->
                                if (last != null) {
                                    handleLocationUpdate(last)
                                }
                            }
                    }
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Immediate location refresh failed: ${e.message}")
                }
        } catch (e: Exception) {
            Log.e(TAG, "triggerImmediateLocationUpload exception: ${e.message}")
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Continuous location tracking for child safety"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guarden")
            .setContentText("Location tracking active")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun setupLocationCallback() {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    handleLocationUpdate(location)
                }
            }
        }
    }

    private fun startLocationUpdates() {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Location permission not granted")
            stopSelf()
            return
        }

        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            5 * 60 * 1000L // 5 minutes
        ).apply {
            setMinUpdateDistanceMeters(100f) // 100 meters
            setWaitForAccurateLocation(false)
            setMaxUpdateDelayMillis(10 * 60 * 1000L) // 10 minutes max delay
        }.build()

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
            Log.d(TAG, "Location updates started")
            
            // Get initial location
            fusedLocationClient.lastLocation.addOnSuccessListener { location ->
                location?.let { handleLocationUpdate(it) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting location updates: ${e.message}")
        }
    }

    private fun stopLocationUpdates() {
        try {
            fusedLocationClient.removeLocationUpdates(locationCallback)
            Log.d(TAG, "Location updates stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error removing location updates: ${e.message}")
        }
    }

    private fun handleLocationUpdate(location: Location) {
        Log.d(TAG, "Location update: ${location.latitude}, ${location.longitude}")
        
        // Check if we should upload this location
        if (shouldUploadLocation(location)) {
            uploadLocationToFirestore(location)
        }
        
        lastLocation = location
    }

    private fun shouldUploadLocation(location: Location): Boolean {
        // Always upload if this is the first location
        if (lastLocation == null) return true
        
        // Upload if enough time has passed
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastUploadTime >= UPLOAD_INTERVAL_MS) return true
        
        // Upload if moved significant distance
        val distance = lastLocation!!.distanceTo(location)
        if (distance >= MIN_DISTANCE_METERS) return true
        
        return false
    }

    private fun uploadLocationToFirestore(location: Location) {
        val user = auth.currentUser
        if (user == null) {
            Log.w(TAG, "No user logged in, cannot upload location")
            return
        }

        val locationData: HashMap<String, Any> = hashMapOf(
            "childId" to user.uid,
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to location.accuracy,
            "altitude" to location.altitude,
            "speed" to location.speed,
            "heading" to location.bearing,
            "timestamp" to com.google.firebase.Timestamp.now(),
            "isMoving" to (location.speed > 0.5)
        )

        // Update current location
        firestore.collection("users")
            .document(user.uid)
            .collection("location")
            .document("current")
            .set(locationData, SetOptions.merge())
            .addOnSuccessListener {
                Log.d(TAG, "Current location uploaded successfully")
                lastUploadTime = System.currentTimeMillis()
                
                // Also add to history
                addToLocationHistory(user.uid, locationData)
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Error uploading location: ${e.message}")
            }
    }

    private fun addToLocationHistory(userId: String, locationData: HashMap<String, Any>) {
        firestore.collection("users")
            .document(userId)
            .collection("location_history")
            .add(locationData)
            .addOnSuccessListener {
                Log.d(TAG, "Location added to history")
            }
            .addOnFailureListener { e ->
                Log.e(TAG, "Error adding to location history: ${e.message}")
            }
    }
}
