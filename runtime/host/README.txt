WordCore for shared hosting (cPanel)
====================================

1. Open cPanel from your host's dashboard and go to File Manager.

2. Open public_html (or the folder of the domain you want to use),
   click Upload and upload this zip.

3. Back in File Manager, right-click the zip and choose Extract.
   You get a folder called "wordcore". The site will live at
   https://your-domain/wordcore/ . To put it at the root of the domain
   instead, move everything inside "wordcore" (including the hidden
   .htaccess) up into public_html.

4. Check that "wordcore.cgi" has permissions 755 (right-click >
   Change Permissions). Most hosts keep this from the zip.

5. Visit the site in your browser. It asks for a setup code: in File
   Manager open  wordcore/site/setup-code.txt  and type the code from it.
   Only someone with access to your files can see it, so nobody else can
   claim your site first.

6. Follow the five setup steps. The setup code file is deleted
   automatically when you're done.

Updating to a new version: upload only the new wordcore.cgi from the zip
over the old one (keep the site folder) and check it is still 755. The
database is updated automatically on the next visit.

If you see an error instead:
   - "500 Internal Server Error": in cPanel open Metrics > Errors and copy
     the newest lines that mention wordcore.
   - The page downloads a file or shows the .htaccess text: CGI isn't
     enabled for this folder. Ask your host whether CGI scripts are allowed.
   - "403 Forbidden": check step 4 (permissions).

Files:
   wordcore.cgi        the WordCore program (Linux x86_64)
   .htaccess           sends requests to the program (hidden file - turn on
                       "Show Hidden Files" in File Manager settings to see it)
   site/               your site's data: database, settings (blocked from the web)
   public/             files served directly by the web server
   NOTICES.txt         licences of the software inside the program
