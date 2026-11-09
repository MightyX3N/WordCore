WordCore - run on your computer
===============================

Start it:
   Windows:  double-click wordcore.exe
   macOS / Linux:  open a terminal in this folder and run  ./wordcore

The first time, your browser opens the setup page by itself (with the
setup code already filled in). If it doesn't, the window shows the
address to open. Afterwards, sign in at  http://localhost:8080/admin
(if port 8080 is busy, the window shows which port it picked).

Stop it with Ctrl+C or by closing the window.
Your site is kept in the "site" folder next to the program - to move or
back up the site, copy that folder.

Other options:
   wordcore serve --port 9000         use another port
   wordcore serve --trust-proxy       when sharing through a tunnel such as playit.gg
   wordcore version

First start warnings (the program isn't code-signed yet):
   Windows:  "Windows protected your PC" > More info > Run anyway
   macOS:    right-click wordcore > Open > Open, or run
             xattr -d com.apple.quarantine wordcore
