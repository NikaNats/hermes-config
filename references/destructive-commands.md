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
    # --- R-02 additions (71 total): wrapper/path/flag variants ---
    bash -c *           sh -c *             dash -c *           zsh -c *
    /bin/bash -c *      /bin/sh -c *
    python -c *         python3 -c *        perl -e *           ruby -e *       node -e *
    /bin/rm -rf *       /usr/bin/rm -rf *
    rm -r -f *          rm -f -r *
    (sudo *             (rm -rf *
    /usr/bin/find / -delete*    /bin/find / -delete*
    find / -exec sudo * find /home -delete*
    env rm -rf *
    eval *              exec sudo *

> **This table documents the R-02 baseline (71) plus the R-04 additions below.**
> The **live, canonical list is 164 patterns** (2026-08-07-r15) — version-controlled
> at `references/deny-patterns.json` and restored by `scripts/update-config-deny.py`.
> It adds the R-14 docker-escape rows and the R-15 rows (interpreter absolute
> paths, service control, docker escalation). The script is the single source
> of truth; this file describes the policy family.

Notes:
- `git push --force-with-lease` is covered by the `git push --force*` pattern.
- `rmdir /s` (Windows cmd) is irrelevant to WSL bash and is not matched.
- Wrapper/interpreter execution (`bash -c`, `python3 -c`, `perl -e`, `eval`, …) is
  deny-listed (R-02) — benign inline `python3 -c` must now run from a script file.

## Shell-layer scanner (defense-in-depth, R-02)

`scripts/hardline-check.sh` blocks what prefix globs cannot see: pipe-to-shell
(`curl | sh`, `echo x | base64 -d | sh`), command substitution of remote fetches
(`$(curl ...)`, `` `wget ...` ``), decode-to-pipeline (`base64 -d | ...`),
eval/exec of fetched content, and recursive-delete of root/home via variables or
reordered flags. Run:

    scripts/hardline-check.sh '<candidate command line>'   # exit 1 = BLOCK

`approvals.smart_policy` rule 9 instructs the Guardian to invoke it pre-execution
on any command not already deny-listed.

## Policy-only (documented, require human review)

`systemctl stop*` and `systemctl disable*` ARE prefix-denied for direct agent
invocation (deny list rows 18–19). What the prefix matcher cannot see —
chained/sudo-mediated variants and SQL statements — stays policy-only:

    sudo systemctl stop <service>            # sudo denied too; human runs it
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
