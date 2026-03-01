# AI Consultant Action System Guide

## Overview
The AI Consultant can now automatically execute control functions based on parent requests. When a parent asks the AI to perform an action (like setting app time limits, blocking apps, or adding rewards), the AI will execute those actions directly.

## How It Works

### 1. User Flow
```
Parent: "Can you set the game app time limit to 30 minutes?"
  ↓
AI receives request and processes it
  ↓
AI Responds: "Sure, I'll set the game time limit to 30 minutes."
+ Includes action tag: <action>{"type":"set_app_time_limit", ...}</action>
  ↓
App parses the action from response
  ↓
App executes the action automatically
  ↓
Parent sees success notification: "✓ Time limit for Game App set to 30 minutes."
```

### 2. Available Actions

#### Set App Time Limit
```json
<action>{"type":"set_app_time_limit", "packageName":"com.example.game", "appName":"Game App", "minutes":30}</action>
```
- Restricts daily usage of a specific app

#### Set Daily Screen Limit
```json
<action>{"type":"set_daily_screen_limit", "screenTimeMinutes":120}</action>
```
- Sets overall daily screen time allowance

#### Block App
```json
<action>{"type":"block_app", "packageName":"com.example.app", "appName":"App Name"}</action>
```
- Completely blocks an app from use

#### Unblock App
```json
<action>{"type":"unblock_app", "packageName":"com.example.app"}</action>
```
- Removes a block on an app

#### Add Custom Reward
```json
<action>{"type":"add_reward", "rewardText":"Movie Night"}</action>
```
- Adds a custom reward to the reward system

### 3. AI Prompt Instructions
The AI is instructed to:
1. Understand when a parent is requesting to execute an action
2. Response positively to the request
3. Include the action tag in the proper JSON format
4. Provide conversational confirmation after the action tag

Example AI Behavior:
```
User: "The app is consuming too much, block it"
AI: "I'll block that app immediately. <action>{"type":"block_app", "packageName":"...", "appName":"..."}</action> 
The app is now blocked and your child won't be able to access it."
```

## Implementation Details

### Files Modified

#### New Files Created
- `lib/models/consultant_action.dart` - Action model and parser
- `lib/services/consultant_action_executor.dart` - Action execution logic

#### Modified Files
- `lib/services/ai_summary_service.dart` - Updated AI prompts
- `lib/ui/parents/chatbot/chatbot_page.dart` - Action parsing and execution

### Key Components

#### ConsultantAction Model
- Parses actions from AI responses
- Extracts JSON from response text
- Cleans response text (removes action tags)

#### ConsultantActionExecutor
- Executes each action type
- Integrates with existing services (AppTimeLimitsService, BlockedAppsService, MarketService)
- Returns success/error messages

#### ChatbotPage Integration
- Parses every AI response for actions
- Executes actions asynchronously
- Shows success/error notifications
- Maintains conversation flow

## Usage Examples

### Example 1: Setting App Time Limit
```
Parent: "My child plays too much video games. Can you limit TikTok to 15 minutes daily?"

AI Response:
"I understand. Let me set a daily 15-minute limit for TikTok so your child can enjoy it responsibly.
<action>{"type":"set_app_time_limit", "packageName":"com.zhiliaoapp.musically", "appName":"TikTok", "minutes":15}</action>
The limit is now active. Your child will receive a notification when they're approaching the time limit."

Result: ✓ Time limit for TikTok set to 15 minutes.
```

### Example 2: Overall Screen Time Limit
```
Parent: "I want to limit total screen time to 2 hours per day"

AI Response:
"That's a good approach. Let me set the daily screen time limit to 2 hours.
<action>{"type":"set_daily_screen_limit", "screenTimeMinutes":120}</action>
Your child now has a 2-hour daily screen time allowance."

Result: ✓ Daily screen time limit set to 120 minutes.
```

### Example 3: Blocking an App
```
Parent: "Block the YouTube app for now"

AI Response:
"I'll block YouTube immediately.
<action>{"type":"block_app", "packageName":"com.google.android.youtube", "appName":"YouTube"}</action>
YouTube is now completely blocked. Your child won't be able to access it."

Result: ✓ YouTube has been blocked.
```

### Example 4: Adding a Reward
```
Parent: "Add a reward for completing homework - Movie night"

AI Response:
"Great! Let me add that reward to your system.
<action>{"type":"add_reward", "rewardText":"Movie Night"}</action>
The 'Movie Night' reward is now available for your child to earn!"

Result: ✓ Reward "Movie Night" has been added.
```

## Error Handling

If an action fails:
- Error notification appears: "Action failed: [error details]"
- Parent can see what went wrong
- Conversation continues normally
- Parent can retry or ask AI to try again

## Natural Conversation Flow

The system maintains natural conversation:
- AI explains the action in human-friendly language
- Action tag is separate from the conversational text
- No technical jargon appears to the parent
- Confirmation messages are clear and reassuring

## Integration with Existing Systems

All actions integrate seamlessly with:
- `AppTimeLimitsService` - manages per-app time limits
- `BlockedAppsService` - manages blocked apps
- `MarketService` - manages rewards
- Firestore backend - stores all data

## Security Considerations

✓ Actions are only executed within the AI chat context  
✓ Only affects the specific child being consulted  
✓ Requires parent authentication (user logged in)  
✓ All actions are logged in Firestore  
✓ Actions can't access unauthorized data  
✓ Follows AGENTS.md security guidelines  

## Testing the Feature

1. Open the chat with AI Consultant
2. Ask it to perform an action:
   - "Set TikTok to 30 minutes"
   - "Block YouTube"
   - "Add a reward"
3. Observe:
   - AI responds appropriately
   - Success notification appears
   - Navigate to Control page to verify action was applied

## Future Enhancements

- [ ] Undo actions from chat
- [ ] Batch actions (multiple actions in one message)
- [ ] Action confirmation prompts
- [ ] Action history in chat
- [ ] Parameter suggestions from AI
- [ ] Complex conditional actions
