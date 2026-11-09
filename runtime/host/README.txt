WordCore — host test
====================

This checks that WordCore can run on your web hosting. It doesn't touch
anything else on your account and you can delete it afterwards.

1. Open cPanel from your host's dashboard and go to File Manager.

2. Open public_html (or the folder of the domain you want to test),
   click Upload and upload this zip.

3. Back in File Manager, right-click the zip and choose Extract.
   You get a folder called "wordcore-test".

4. Open the folder and check that "wordcore.cgi" has permissions 755
   (right-click > Change Permissions: Owner read/write/execute,
   Group and World read/execute). Most hosts keep this from the zip.

5. Visit  https://your-domain/wordcore-test/  in your browser.

   - A "Host check" page with green ticks means WordCore works on this host.
   - Reload it a few times: the visit counter should go up.

If you see an error instead:
   - "500 Internal Server Error": in cPanel open Metrics > Errors and copy
     the newest lines that mention wordcore.
   - The page downloads a file or shows the .htaccess text: CGI isn't
     enabled for this folder. Ask your host whether CGI scripts are allowed.
   - "403 Forbidden": check step 4 (permissions).

When you're done, delete the "wordcore-test" folder.

Files:
   wordcore.cgi        the WordCore program (Linux x86_64)
   .htaccess           sends requests to the program (hidden file — turn on
                       "Show Hidden Files" in File Manager settings to see it)
   public/hello.txt    checks that normal files are still served directly
   site/               where WordCore keeps its data (blocked from the web)
   NOTICES.txt         licences of the software inside the program
