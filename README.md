# `cliptic`: Crosswords in your Terminal

![](https://github.com/apexatoll/cliptic-files/blob/master/demo.gif)


- A command-line interface for downloading and playing cryptic crosswords from within the terminal. 
- Puzzles are sourced from the free crosswords uploaded daily to [Lovatt's][1]. 
- cliptic is written in Ruby using the ncurses library

## New to 0.1.2

### Bug Fixes
- Screen setup/config file bug fix
	* Previously screen resize prompt would not show if screen was too small due to inability to source default colours
- Fix earliest date bug (thank you `samtell21` for pointing this out)
- Center the resize prompt

### Features
- Add menu recolour feature

## Features
- VIM-like keybindings
- Puzzles scraped daily from Lovatt's. Puzzles are cached locally to prevent excessive requests
- Progress can be saved to continue puzzles at a later time
- Time taken to complete the puzzle is logged on completion of puzzle. High scores can be viewed within cliptic
- Track progress for puzzles released in the last week
- Puzzle history is tracked, making it easy to pick up recently played puzzles
- Select puzzles to play by date manually (puzzles are available for up to 9 months from release)
- Customisation of cliptic's appearance

## Dependencies

### System
- Ruby
- Ncurses
- Curl

### Gems
- curb
- curses
- sqlite3

## Installing

### As a Gem
- cliptic is available as a Ruby Gem. To install, simply run:
```bash
gem install cliptic
```
### Manually
- Or, to install manually:
```bash
git clone https://github.com/apexatoll/cliptic
cd cliptic
rake build install
```

## Running
- To run cliptic after installation, simply run the command `cliptic` from within the terminal
- When the program is first run it will ask the user whether they want cliptic to generate a default config file. This is located in `~/.config/cliptic/cliptic.rc`
- If the screen is too small to display cliptic, please resize until the prompt disappears

### Other Commands
- There are other commands that can be run from the command line

#### Today
- The command `cliptic today` will play today's puzzle
- This command can be followed with a negative number to play a puzzle n days before today
- For example `cliptic today -2` will play the puzzle from the day before yesterday

#### Resetting Progress
- The command `cliptic reset` will allow the user to reset progress in cliptic.
- The command can be followed with either `all`, `states`, `scores` or `recents`
- `all` resets all progress
- `states` resets all game progress
- `scores` resets high scores
- `recents` resets puzzle history

## Main Menu
- On the main menu there are several options 
	* Play today's puzzle
	* Show this week's progress
	* Select a date manually
	* Display recent puzzles
	* Show high scores
	* Exit cliptic

### Menu Navigation
| Command          | Action         |
|------------------|----------------|
| `j/DOWN`, `k/UP` | Move cursor    |
| `q`              | Back/quit      |
| `ENTER`          | Make selection |
	
## Solving Puzzles
- By default, cliptic uses vim-like keybindings for navigation and text manipulation. There are plans to release more "accessible" keybindings in the future.
- Text manipulation is modal akin to vim. Vim-users will be familiar with insert and normal modes
- The currently focussed clue is displayed within the window at the bottom of the screen. If you are on a cell that is an intersection of two clues (ie an across and a down) you can swap between them using `TAB`

### Game Modes
- There are 2 game modes that can be played. These can be changed in the cliptic config file.
1. *Auto_mark* = 1 (default)
	- Each clue is marked once every cell is filled
	- The clue will be highlighted green or red depending on whether the attempt is correct
2. *Auto_mark* = 0
	- No clues are marked automatically, similar to a paper crossword 
	- Clues can be checked manually using the `^G` command

### Global Commands

| Command | Action                                                                                                 |
|---------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `^S`    | Save current progress (note that progress is saved when exiting puzzles by default)                |
| `^R`    | Reveals solution for focussed clue (note that this forfeits adding this puzzle to high scores) |
| `^C`    | Exit puzzle                                                                                            |
| `^E`    | Resets timer and progress for puzzle                                                                   |
| `^G`    | Mark current progress (only relevant if auto_mark is set to 0)                                         |
| `^P`    | Pause game                                                                                             |

### Navigation (Normal Mode)
- There are several ways to navigate the cells of the cliptic grid in **NORMAL MODE**.

| Command            | Action                                                         |
|--------------------|----------------------------------------------------------------|
| `h`, `j`, `k`, `l` | Move cursor left, up, down, right. Arrow keys can also be used |
| `(n)w`             | Move to (nth) next unsolved clue                               |
| `(n)b`             | Move to (nth) previous unsolved clue                           |
| `e`                | Move to end of clue                                            |
| `<clue number>g`   | Move to clue by number                                         |
| `<cell number>G`   | Move to cell by number (not 0 indexed                          |
| `TAB`              | Swap from across to down clue (or vice versa)                  |

### Entering Text (Insert Mode)

| Command     | Action                              |
|-------------|-------------------------------------|
| `a-z`       | Enter character to cell             |
| `BACKSPACE` | Delete one character                |
| `ESC`       | Exit insert mode. Enter normal mode |

### Normal Mode

| Command   | Action                                                                         |
|-----------|-----------------------------------------------------------------------------------------------------|
| `I`       | Move to the start of the clue and enter insert mode                            |
| `a`       | Advance one cell and enter insert mode                                         |
| `c(obj)`  | calls d(obj) then enters insert mode                                           |
| `d(obj)`  | delete the object provided after d (may be w for word or l for character) |
| `i`       | Enter insert mode                                                              |
| `r(char)` | Replaces the character under the cursor with `char`                            |
| `x`       | deletes the character under the cursor                                         |

## Configuration
- Cliptic settings can be added to the cliptic.rc file found at `~/.config/cliptic/cliptic.rc`

### Interface
- Affect how cliptic functions
- Set using the format
```
set <setting> <0/1>
```

#### Settable Items

| Item           | Description                    | Default |
|----------------|--------------------------------|---------|
| `auto_advance` | Move to next clue after solve  | 1       |
| `auto_mark`    | Mark clues as they are entered | 1       |
| `auto_save`      | Save progress on exit          | 1       |

### Colours
- Colours are numbered 1-16. 
	* 0 is default terminal color
	* 1-8 equates to your terminals 8 default colours. 
	* 9-16 equate to same colours as the background and blank as the foreground
- To set colour settings use the format
```
hi <obj> <colour>
```
	
#### Settable Items

| Item            | Description                | Default |
|-----------------|----------------------------|---------|
| `active_num`    | Grid number of active clue | 3       |
| `bar`           | Top and bottom bars        | 16      |
| `block`         | Grid blocks                | 8       |
| `box`           | Box outlines               | 8       |
| `grid`          | cliptic grids              | 8       |
| `incorrect`     | Incorrect clue attempt     | 1       |
| `correct`       | Correct clue attempt       | 2       |
| `prompt`        | Menu prompt                | 3       |
| `default`       | Default text color         | 0       |
| `meta`          | Clue box metadata          | 3       |
| `num`           | Inactive grid numbers      | 8       |
| `logo_text`     | Logo text color            | 3       |
| `I`             | Insert mode prompt         | 15      |
| `N`             | Normal mode prompt         | 12      |
| `menu_active`   | Active menu option         | 15      |
| `menu_inactive` | Inactive menu option       | 0       |

## Feedback
- Cliptic is still in development
- If you have any feature requests or find any bugs please leave a new issue
- Contributions welcome!

*Dedicated to WES who passed on to me his love of crosswords*

[1]: https://lovattspuzzles.com/online-puzzles-competitions/daily-cryptic-crossword/
