@echo off

node bin/version.js >> temp.txt
set /p gifversion= < temp.txt
del temp.txt

set url=https://github.com/jnordberg/gif.js

if exist node_modules/commonjs-everywhere/lib/command.js (
    echo Packaging gif.js %gifversion%
    node  node_modules/commonjs-everywhere/lib/command.js ^
        --export GIF ^
        --root src/ ^
        --source-map dist/gif.js.map ^
        --output dist/gif.js ^
        --inline-sources ^
        --minify ^
        gif.coffee
    echo. >> dist/gif.js
    echo // gif.js %gifversion% - %url% >> dist/gif.js
    node  node_modules/commonjs-everywhere/lib/command.js ^
        --root src/ ^
        --no-node ^
        --source-map dist/gif.worker.js.map ^
        --output dist/gif.worker.js ^
        --inline-sources ^
        --minify ^
        gif.worker.coffee
    echo. >> dist/gif.worker.js
    echo // gif.worker.js %gifversion% - %url% >> dist/gif.worker.js
    echo build done!
) else (
    echo Dependencies missing. Run npm install
)