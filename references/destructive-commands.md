# Destructive Command Controls (spec 5.5)

Blocked or explicit-confirmation commands. Enforcement split:

## Enforced by approvals.deny (agent cannot run at all)

    rm -rf /            rm -rf ~            rm -rf /*           rm -rf ~/*
    sudo *              env sudo *          /usr/bin/env sudo *
    /usr/bin/sudo *     /bin/sudo *
    chmod -R 777 *      chown -R *
    curl * | *sh        wget * | *sh        curl *|*sh          wget *|*sh
    curl * | *python*   curl * | *node*     curl * | *ruby*     curl * | *perl*
    wget * | *python*   wget * | *node*     wget * | *ruby*     wget * | *perl*
    git push --force*   git push origin +*  git push +*
    git reset --hard*   git clean -fd*
    git checkout -- .   git branch -D*      git rebase -i*
    dd if=*             mkfs*               fdisk /dev*         parted /dev*
    systemctl stop*     systemctl disable*
    iptables -F*
    docker system prune*
    kubectl delete*
    terraform destroy*  pulumi destroy*
    ansible-playbook --check=false*
    shutdown*           reboot*
    find / -delete*     find / -exec rm*

Notes:
- `git push --force-with-lease` is covered by the `git push --force*` pattern.
- `rmdir /s` (Windows cmd) is irrelevant to WSL bash and is not matched.

## Policy-only (documented, require human review — not shell-prefix matchable)

    systemctl stop/disable on production services
    DROP TABLE / TRUNCATE / DELETE FROM without WHERE
    database migrations

SQL destructive statements cannot be caught by command-prefix matching; the
agent must propose them with a reviewable plan (Pattern 2), and the human
runs them inside a transaction with a backup.

## Safer alternative to deletion: trash

Helper in this repo:

    scripts/trash.sh target-directory
    # -> ~/.local/share/Trash/files/target-directory-<timestamp>

or trash-cli if installed (not yet):

    sudo apt install -y trash-cli
    trash-put unwanted-file
