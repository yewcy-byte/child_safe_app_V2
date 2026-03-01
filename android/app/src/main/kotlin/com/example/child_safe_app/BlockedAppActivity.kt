package com.example.child_safe_app

import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.app.Activity
import android.graphics.Typeface
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView

class BlockedAppActivity : Activity() {

    companion object {
        private const val EXTRA_PACKAGE_NAME = "packageName"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val imageView = ImageView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            scaleType = ImageView.ScaleType.FIT_XY
            try {
                assets.open("flutter_assets/assets/images/blockApp.png").use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    setImageBitmap(bitmap)
                }
            } catch (_: Exception) {
                setBackgroundColor(Color.BLACK)
            }
        }

        val homeButton = Button(this).apply {
            text = "Exit To Home Screen"
            setTextColor(Color.WHITE)
            textSize = 18f
            try {
                typeface = Typeface.createFromAsset(assets, "flutter_assets/assets/fonts/ComicNeueSansID.ttf")
            } catch (_: Exception) {
                typeface = Typeface.SANS_SERIF
            }
            setPadding(60, 30, 60, 30)
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(Color.parseColor("#8ac1ff"))
                cornerRadius = 24f
            }
            setOnClickListener {
                val goHome = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(goHome)
                finish()
            }
        }

        val buttonParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        ).apply {
            setMargins(40, 40, 40, 100)
        }

        root.addView(imageView)
        root.addView(homeButton, buttonParams)

        setContentView(root)
    }
}
