REF_IMAGES - Image-Based Detection Reference
=============================================

This folder contains the reference images that the script uses to detect
UI elements via OpenCV template matching. Save the screenshots you sent
me with the exact filenames below.

POPUPS (handled automatically when they appear)
-----------------------------------------------
popup_notice_error.png       - NOTICE popup: "Connection timed out..."
popup_hint_update.png        - HINT popup: "New version available..."
popup_banned_reminder.png    - Reminder popup: "Sorry, this account has been banned..."

POPUP BUTTONS
-------------
btn_confirm_blue.png         - Blue CONFIRM button (used in NOTICE/HINT)
btn_quit_red.png             - Red QUIT button (in HINT popup)
btn_switch_accounts.png      - Red "Switch Accounts" button (in Banned Reminder)

LOGIN SCREEN
------------
field_email.png              - Gray "Email Address" field (top of login dialog)
btn_code_login.png           - Red "Verification Code Login" button
field_code_input.png         - 6-box "Verification Code" input field

GAME UI (small icons - must be precise)
---------------------------------------
splash_tap_to_start.png      - Rise of Kingdoms splash with "Tap to Start" at bottom
icon_profile_avatar.png      - Small circular avatar (top-left of main city)
icon_settings_gear.png       - Small gear icon (right side of profile screen)
icon_general_settings.png    - Small gear icon (in settings dialog)
icon_customization.png       - Blue customization icon (left sidebar)

TOGGLES
-------
toggle_off.png               - Gray toggle (OFF state)
toggle_on_blue.png           - Blue toggle (ON state)
toggle_on_green.png          - Green toggle (ON state)

CAPTCHA
-------
captcha_slider.png           - "Slide to complete the puzzle" captcha


HOW THE SCRIPT USES THESE
-------------------------
1. Handle-Popups is called between EVERY action. It searches for the
   popup reference, and if found, taps the corresponding dismiss button.

2. State machine (Process-LoginOptimize):
   [HOME] -> [LAUNCH] -> [SPLASH] -> [LOGIN] -> [CODE] -> [CITY] ->
   [PROFILE] -> [SETTINGS] -> [OPTIMIZE] -> [EXIT]

3. Each state has a primary image-based action and a coordinate-based
   fallback if the image isn't found.

4. Toggle optimization finds any OFF toggle and taps it to turn ON.

5. IMAP runs in a background job that polls Gmail every 5s. The main
   thread checks for the verification code via shared file every 3s.

TESTING
-------
Run: python Tools/find_image.py <screenshot.png> <ref.png> 0.75
Should output: cx,cy,w,h,confidence
