# Snapshots & Rollback

Maze takes a btrfs snapshot automatically **before and after every `pacman`
transaction** (via snap-pac). You do not need to remember to do it, and you do
not need to configure anything.

## Listing snapshots

```bash
snapper -c root list
```

Graphical equivalent: **Btrfs Assistant**, in the application menu.

## Undoing a single change

This is the common case: an update changed something and you want it back the
way it was. First see what actually changed between snapshot 42 and now:

```bash
sudo snapper -c root status 42..0
```

Then undo it:

```bash
sudo snapper -c root undochange 42..0
```

File-level undo works reliably. Use it freely.

## Full system rollback

Returning the entire system to an earlier snapshot needs one extra setup step,
because it changes how the system boots:

```bash
sudo maze-enable-rollback           # shows what would change
sudo maze-enable-rollback --apply   # applies it
```

After that:

```bash
sudo maze-rollback                  # list snapshots you can return to
sudo maze-rollback 42               # return to snapshot 42
```

> **Known limitation:** full system rollback is **not yet reliable on every
> machine** and is still being worked on. File-level undo, described above, is
> solid. If you need to recover from a bad update today, prefer
> `snapper undochange` or the [recovery kernel](Recovery).

## What snapshots do not protect against

Snapshots live on the same disk as your system. They protect you from a bad
update or a mistaken change — **not** from disk failure, theft, or an
encrypted-disk password you have forgotten. Keep real backups on separate
media for that.

See also: [If the System Won't Boot](Recovery) · [Updating](Updating)
