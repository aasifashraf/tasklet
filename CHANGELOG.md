# Changelog

## 1.1.0, November 2026

- Organizations: each one is its own data folder with its own projects, labels and quick filters, so work,
  freelance and open source stay apart and can sync through different services. Switch from the top of the sidebar,
  the Organization menu or Ctrl+Alt+1 to 9. New Organization asks for a name, icon and location; Open Existing
  Folder adds a folder from another computer. Settings > Organizations renames, reorders, relocates or forgets them
  (files are never deleted). The window title names the open one. Your current folder becomes your first
  organization.
- Move a project to another organization from its menu: it is written there before it is removed here, with the
  labels its tasks use and the same task numbers
- Export an organization to one `.tasklet.json` file and import it as a new organization
- Icons for projects, labels and quick filters: about 640 project-related icons (Lucide) with search, recents and
  a color row; quick filters show a filter icon by default
- A new organization starts with bug, feature, refactor and security labels and five everyday quick filters
  (Overdue, Due Soon and High Priority pinned, In Progress, No Due Date); the first one also gets a sample Tasklet
  project showing Tasklet's plan. Folders that already have data are never changed
- 16 colors (teal, cyan, indigo, pink, lime, amber, brown and slate added); green, orange and yellow are darker in
  the light theme so every color reads on every background
- Boards patch only the tasks that changed after an edit (about 20 ms instead of 170 ms with 100,000 tasks), search
  is faster, and typing more of a search filters the previous result

## 1.0.3, November 2026

- Restore earlier versions: Tasklet keeps recent versions of each project, the workspace labels and the quick
  filters on this computer (at most one every 10 minutes, the newest 20). Restore Previous Version is in each
  project's menu and behind the history button on the Labels and Quick Filters pages; the current version is kept
  first, so a restore can be undone
- Repairs after syncing, with a notice saying what changed: duplicate task numbers from two computers get the next
  free number (the oldest keeps its number), and a task found in two project files is kept once (the most recently
  edited copy)
- Invalid project keys are regenerated; filter values written by a newer version are kept; a data folder marker
  without a format version no longer makes the folder read-only; files over 100 MB are left untouched
- Undo changes back only what it changed, and says so when the task no longer exists
- The task panel stays open when its task moves to another project
- Dropping a card between two cards with the same position puts it exactly there
- Opening Settings twice quickly opens one window and restores a minimized one
- The folder watcher reports changes at least every 2 seconds during heavy syncing
- Reports: done tasks without a completion time count as completed, no negative durations, fast very long ranges
- Choosing or creating a data folder explains failures

## 1.0.2, November 2026

- Fast with big workspaces: large folders open without freezing and switching back to Tasklet is instant, even with
  tens of thousands of tasks (files are re-read only when they change, big files are parsed in the background)
- Your last edit is saved when you quit from the tray or File → Exit
- Changes made in the Settings window and the main window no longer overwrite each other
- A data folder that goes missing (for example an unplugged drive) is never recreated empty
- Moving a task to another project can no longer lose it if saving fails
- New Task can no longer create the same task twice
- Search keeps up while you type on large boards
- Easier-to-read secondary text in the light theme
- The list layout scrollbar works correctly
- Errors are written to a local log file (`logs/tasklet.log` in the app's settings folder) to help with bug reports
- What's New now shows every release, newest first

## 1.0.1, November 2026

First public release (Windows).

- Board and list layouts with drag and drop, sorting, filters and search
- Projects with stable task IDs, labels, favorites, archive, and quick filters
- Today page and Dashboard
- New Task dialog, autosaving detail panel, full right-click menu, and Undo for every change
- Daily due-date reminders; Tasklet keeps running in the tray when its window is closed
- Reports: copy an AI-ready prompt or JSON for any assistant (no data leaves your computer)
- Separate Settings window, light/dark themes, customizable sidebar, keyboard shortcuts
- Safe storage: atomic writes, unreadable files never overwritten, sync conflict copies left untouched
- Windows installer (no admin rights needed) and portable zip
