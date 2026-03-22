# Upload code only (exclude data/ so remote keeps its own DB and logs)
scp server.js package.json package-lock.json README.md upload.sh dictionary@dict.liusida.com:~/zimo-usage/
scp -r public dictionary@dict.liusida.com:~/zimo-usage/
