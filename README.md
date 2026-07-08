# Ergo-L TTY Builder

A set of scripts to build, test, and load the Ergo-L keyboard layout in a Linux TTY.

## Build a Map

> [!IMPORTANT]
> Requires the `eurlatgr` font installed on your system to build the map correctly.

Run the builder script:
```sh
./ergol-builder.sh # Build a map
```
If the build fails, check the following troubleshooting files:
- `./built.map` (The generated map output)
- `./ergol_builder.log` (The build logs)

## Check map syntax

Since `loadkeys` is notoriously quiet about syntax errors, this script helps isolate the exact problematic line in a map file.
Run it inside a TTY:
```sh
./loadkey_tester.sh ./built.map
```

Log output will be written to `loadkey_tester.log` 

## Load the Layout

Once verified, you can apply the layout in your TTY with:
```sh
loadkeys ./fr-ergol.map.gz
```
