## [0.1.0] - 2021-07-08

- Initial release

## [0.1.1] - 2021-07-11

- Minor change to fix screen setup bug

## [0.1.2] - 2021-07-15

### Bug Fixes
- Screen setup/config file bug fix
	* Previously screen resize prompt would not show if screen was too small due to inability to source default colours
- Fix earliest date bug 
- Center the resize prompt

### Features
- Add menu recolour feature

## [0.1.3] - 2021-10-01

### Bug Fixes
- Fix the ssl certificate bug that prevents fetching puzzles
- Fix the "out of range" bug when moving to an undefined index using `g`

### Features
- Add manual redraw feature to the main puzzle view. Called with `^L` (useful for terminal resize)
- Add exit controls to the resize interface (`q` or `^C`)
