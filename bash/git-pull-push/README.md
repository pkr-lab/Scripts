### Installation

```bash
git clone <URL> /opt/git/mein-projekt
install -m 0755 git-pull-push.sh /usr/local/bin/git-pull-push.sh
git-pull-push.sh --check
```

### Täglicher Lauf

```bash
crontab -e
0 4 * * * /usr/local/bin/git-pull-push.sh >> /var/log/git-pull-push.log 2>&1
```
