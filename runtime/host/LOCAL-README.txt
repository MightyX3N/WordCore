WordCore — run on your computer
===============================

Start it:
   Windows:  double-click wordcore.exe
   macOS / Linux:  open a terminal in this folder and run  ./wordcore

Then open  http://localhost:8080  in your browser. Stop it with Ctrl+C
(or close the window).

The site's data is kept in the "site" folder next to the program.

Other options:
   wordcore serve --port 9000         use another port
   wordcore serve --trust-proxy       when sharing through a tunnel such as playit.gg
   wordcore version

First start warnings (the program isn't code-signed yet):
   Windows:  "Windows protected your PC" > More info > Run anyway
   macOS:    right-click wordcore > Open > Open, or run
             xattr -d com.apple.quarantine wordcore
