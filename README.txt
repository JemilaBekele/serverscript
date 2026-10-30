===============================================================================
  drlemlem - SERVER SCRIPTS GUIDE
  Start, stop, back up and restore the system on the server PC
===============================================================================

This folder holds the scripts that run drlemlem on the server PC.
It must sit next to the two system folders, like this:

    <system folder>\
        smartdent-backend\      (the API)
        smartdent-frontend\     (the website)
        server-scripts\         (this folder)

The scripts find everything from their own location, so the system folder
can be anywhere (default C:\smartdent\Branch-smartdent).


-------------------------------------------------------------------------------
 1. WHAT EACH FILE DOES
-------------------------------------------------------------------------------

  config.bat          Settings. The ONLY file you normally edit.
  start-system.bat    Starts the backend and the website. Restarts either one
                      10 seconds after it stops or crashes.
  stop-system.bat     Stops the backend and the website.
  RunServer.vbs       Runs start-system.bat with no window (for Task Scheduler).
  backup.bat          Backs up the database and the patient images.
  RunBackup.vbs       Runs backup.bat with no window (for Task Scheduler).
  restore.bat         Restores the database from a backup.
  install-tasks.bat   Creates the two Task Scheduler tasks for you, and keeps
                      the PC awake while plugged in (no sleep, lid does nothing)
                      so other branches can always reach it.
  install-tasks.ps1   Used by install-tasks.bat (do not run directly).
  install-release.bat Installs a new version from a release zip (section 8).
  install-release.ps1 Used by install-release.bat (do not run directly).
  run-backend.bat     Used by start-system.bat (do not run directly).
  run-frontend.bat    Used by start-system.bat (do not run directly).
  logs\               Created automatically. Holds the log files.


-------------------------------------------------------------------------------
 2. FIRST-TIME SETUP (do once)
-------------------------------------------------------------------------------

 Step 1 - Install on the server PC
   - Node.js 22 LTS (nodejs.org)
   - pnpm:  open a command prompt and run   npm install -g pnpm
   - MongoDB Database Tools (for backup and restore). They install to
     C:\Program Files\MongoDB\Tools\100\bin

 Step 2 - Check the backend settings
   Open smartdent-backend\.env and make sure these lines are right:

       NODE_ENV=production
       PORT=7000
       MONGODB_URI=<your database address>
       COOKIE_SECURE=false            (only for plain http:// on the clinic network)
       CORS_ORIGIN=http://localhost:3090
       TRUST_PROXY=0
       RATE_LIMIT_ANON_MAX=1000

 Step 3 - Check the website settings
   Open smartdent-frontend\.env.production. The port must match the backend:

       NEXT_PUBLIC_API_URL=/api/v1
       API_PROXY_TARGET=http://127.0.0.1:7000

 Step 4 - Build both parts (open a command prompt)

       cd <system folder>\smartdent-backend
       npm install
       npm run build

       cd <system folder>\smartdent-frontend
       pnpm install
       pnpm build

 Step 5 - Check config.bat
   Open config.bat in Notepad. Usually you only change:

       BACKUP_ROOT    where backups go (default C:\drlemlem-Backups).
                      Better: a second drive or an external disk, e.g. D:\drlemlem-Backups
       KEEP_DAYS      how many days of database backups to keep
                      (default 0 = keep every backup, never delete)
       FRONTEND_PORT  website port (default 3090)

 Step 6 - Test by hand
   Double-click start-system.bat, wait about 30 seconds, then open
   http://localhost:3090 in the browser and sign in.
   Then double-click stop-system.bat.

 Step 7 - Let other computers connect
   a) Give the server PC a fixed IP address (reserve it in the router).
   b) Open PowerShell AS ADMINISTRATOR and run:

        Set-NetConnectionProfile -NetworkCategory Private
        New-NetFirewallRule -DisplayName "drlemlem" -Direction Inbound -Protocol TCP -LocalPort 3090 -Action Allow -Profile Private

   c) On the other computers open:  http://<server-ip>:3090
      Example: http://192.168.0.142:3090
   Do NOT open port 7000 (backend) or 27017 (MongoDB) in the firewall.


-------------------------------------------------------------------------------
 3. TASK SCHEDULER (start automatically + hourly backup)
-------------------------------------------------------------------------------

 OPTION A - Automatic (recommended)
   Right-click install-tasks.bat > "Run as administrator".
   It creates, in Task Scheduler under the folder "SmartDent"
   (and removes the tasks from the old "AFET Dental" folder, if any):

     Start System   runs at Windows start-up (1 minute delay),
                    even if nobody logs in
     Backup         runs every hour, on the hour; if the PC was off,
                    it runs at the next start-up

   To back up less often (e.g. every 4 hours), run in PowerShell as
   administrator:
       .\install-tasks.ps1 -BackupEveryHours 4

 OPTION B - By hand
   Open Task Scheduler > Create Task...

   Task 1: "drlemlem Start System"
     General  : "Run whether user is logged on or not"
                tick "Run with highest privileges"
     Triggers : New > Begin the task: "At startup"
                (optional: Delay task for 1 minute)
     Actions  : New > Start a program
                Program/script : wscript.exe
                Add arguments  : "<system folder>\server-scripts\RunServer.vbs"
     Settings : untick "Stop the task if it runs longer than"

   Task 2: "drlemlem Backup"
     General  : same as Task 1
     Triggers : New > One time, at 00:00 today; tick "Repeat task every:
                1 hour" for a duration of: Indefinitely
     Actions  : Program/script : wscript.exe
                Add arguments  : "<system folder>\server-scripts\RunBackup.vbs"
     Settings : tick "Run task as soon as possible after a scheduled start
                is missed"

   Keep the quotes around the path in "Add arguments".

 Check it works: in Task Scheduler right-click the task > Run, then look
 in the logs folder (section 5).


-------------------------------------------------------------------------------
 4. DAILY USE
-------------------------------------------------------------------------------

  Start the system      double-click start-system.bat  (or RunServer.vbs for
                        no window). Running it twice is safe: it skips a part
                        that is already running.
  Stop the system       double-click stop-system.bat.
                        If Task Scheduler started it: right-click >
                        "Run as administrator".
  Restart the system    stop-system.bat, then start-system.bat.
  Open the system       http://localhost:3090 on the server,
                        http://<server-ip>:3090 on other computers.


-------------------------------------------------------------------------------
 5. LOG FILES (logs folder)
-------------------------------------------------------------------------------

  system.log     each start and stop
  backend.log    backend messages and errors
  frontend.log   website messages and errors
  backup.log     each backup: "Backup started", "Database saved",
                 "Images copied", "Backup finished" (or "FAILED: ...")

  Logs larger than 10 MB are renamed to .old and a new one is started.
  Check backup.log once a week to make sure backups finish.


-------------------------------------------------------------------------------
 6. BACKUPS
-------------------------------------------------------------------------------

  Each backup creates:

    <BACKUP_ROOT>\2026-10-21_1400\db\   database, compressed (one folder per
                                       run, so one per hour)
    <BACKUP_ROOT>\uploads-mirror\       patient images (X-rays, photos)

  - With KEEP_DAYS=0 (the default) no backup is ever deleted. Check the free
    space on the backup drive once a month: 24 backups are added every day.
    To delete old ones automatically, set KEEP_DAYS in config.bat (e.g. 90).
  - uploads-mirror only receives new and changed images. Nothing is ever
    deleted from it, so an image deleted by mistake can still be found there.
  - Backup by hand any time: double-click backup.bat.
  - The database address is read from smartdent-backend\.env (MONGODB_URI).
    If it is a cloud (Atlas) database, the backup needs internet.
  - Copy the backup folder to an external disk from time to time. A backup on
    the same disk as the system is lost if that disk fails.


-------------------------------------------------------------------------------
 7. RESTORE (recover data from a backup)
-------------------------------------------------------------------------------

  !! WARNING: the restore writes into the LIVE database named in
  !! smartdent-backend\.env. Use it only when you really need to recover.

  1. Double-click restore.bat
       - it picks the NEWEST backup automatically, or
       - to pick a certain backup, open a command prompt in this folder and run:
             restore.bat 2026-10-21_2100
  2. Choose:
       1 = Replace : the database becomes exactly the backup
                     (everything saved after the backup is lost)
       2 = Merge   : only records missing from the database are added back
  3. Type YES to start (anything else cancels without changes).
  4. The script stops the system, restores, and starts the system again.

  To restore images: copy the files you need from
  <BACKUP_ROOT>\uploads-mirror back to smartdent-backend\uploads.


-------------------------------------------------------------------------------
 8. UPDATING THE SYSTEM (new version)
-------------------------------------------------------------------------------

  New versions come from the supplier as one zip file (SmartDent-<date>.zip).
  It holds only the built system - no source code - so nothing is built on
  the server and no internet is needed.

  1. Copy the zip to the server, e.g. C:\SmartDent-2026-10-21_1500.zip
  2. Open Command Prompt AS ADMINISTRATOR and run:

        C:\Smartdent\server-scripts\install-release.bat "C:\SmartDent-2026-10-21_1500.zip"

  It backs up, stops the system, installs the new version, starts it and
  checks it answers. Kept automatically: smartdent-backend\.env,
  license.key, the patient images (uploads) and config.bat.
  If the new version does not start, the old one is put back and started.
  On success the old folders are deleted.

  The first time (moving from a git copy with source code to a release), the
  old folders with the source code are removed this way too.


-------------------------------------------------------------------------------
 9. PROBLEMS AND FIXES
-------------------------------------------------------------------------------

  Website does not open on the server
    - Look at logs\frontend.log and logs\backend.log.
    - "No standalone build"  -> run  pnpm build  in smartdent-frontend
    - "dist\server.js missing" -> run  npm run build  in smartdent-backend

  Website opens but sign-in fails
    - Backend not running: check logs\backend.log.
    - Port mismatch: PORT in smartdent-backend\.env must match the port in
      API_PROXY_TARGET in smartdent-frontend\.env.production.
      After changing .env.production, run  pnpm build  again.

  Other computers cannot open the website
    - Firewall / network set to Public (section 2, step 7).
    - The server's IP changed: give it a fixed IP.
    - Try http://<server-ip>:3090 on the server itself first.

  Staff are signed out after every reload
    - COOKIE_SECURE=false is missing in smartdent-backend\.env (plain http).

  "Too many requests" when signing in
    - Raise RATE_LIMIT_ANON_MAX in smartdent-backend\.env, then restart.

  Backup says FAILED
    - "mongodump.exe not found": install MongoDB Database Tools, or fix
      MONGO_TOOLS in config.bat.
    - "MONGODB_URI not found": check smartdent-backend\.env.
    - Cloud database: check the internet connection.

  stop-system.bat does not stop the system
    - Run it as administrator (Task Scheduler runs the system as SYSTEM).

  System restarts again and again (see backend.log)
    - Usually the database cannot be reached or a .env value is wrong.
      The error is in logs\backend.log just before "Backend stopped".

===============================================================================
