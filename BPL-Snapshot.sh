#!/bin/bash

bitaxeName=$(cat ./config.json | jq .bitaxeName | tr -d '"')

# Input CSV file
CSVFILE="/tmp/BPL/BPL-$bitaxeName-Logging.csv"

# Output directory
OUTPUTDIR="/tmp/BPL"

# Temporary Gnuplot script
TEMPGP=$(mktemp /tmp/BPL/gnuplot.XXXXXX.gp)

# Function to check dependencies
checkdeps() {
    command -v gnuplot >/dev/null 2>&1 || { echo "Error: gnuplot not installed"; exit 1; }
    command -v montage >/dev/null 2>&1 || { echo "Error: imagemagick not installed"; exit 1; }
}

# Function to validate CSV
validatecsv() {
    [[ -f "$CSVFILE" && -r "$CSVFILE" ]] || { echo "Error: $CSVFILE not found or unreadable"; exit 1; }
    [[ -s "$CSVFILE" ]] || { echo "Error: $CSVFILE is empty"; exit 1; }
    NUMCOLUMNS=$(head -n 1 "$CSVFILE" | tr ',' '\n' | awk 'END {print NR}' | tr -d ' \t\r')
    [[ -n "$NUMCOLUMNS" && $NUMCOLUMNS -ge 2 ]] || { echo "Error: CSV must have at least 2 columns"; exit 1; }
}

# Main script
checkdeps
validatecsv

# Get number of y-columns
NUMYCOLUMNS=$((NUMCOLUMNS - 1))

# Get x-column header (first column)
XHEADER=$(head -n 1 "$CSVFILE" | cut -d',' -f1 | tr -d '\r')

# Array to store generated plot filenames
declare -a PLOTFILES

# Initialize single Gnuplot script
echo "set datafile separator \",\"" > "$TEMPGP"

# Loop through y-columns (starting from column 2)
for ((i=2; i<=NUMCOLUMNS; i++)); do
    COLIDX=$((i - 1))
    YHEADER=$(head -n 1 "$CSVFILE" | cut -d',' -f$i | tr -d '\r')
    [[ -z "$YHEADER" ]] && { echo "Warning: Skipping empty header for column $i" >&2; continue; }
    CHARTTITLE="$YHEADER"
    FILENAME=$(echo "$CHARTTITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | sed 's/[^a-z0-9_-]//g' | head -c 50).png
    PLOTFILES+=("$OUTPUTDIR/$FILENAME")
    echo "Generating plot: $CHARTTITLE" >&2

    # Append to Gnuplot script
    cat >> "$TEMPGP" << EOF
set terminal pngcairo size 800,600 enhanced background rgb "#060D17"
set output '$OUTPUTDIR/$FILENAME'
set title '$CHARTTITLE' font ',16' textcolor rgb "white"
set xlabel '$XHEADER' textcolor rgb "#A2A5AC"
set ylabel '$YHEADER' textcolor rgb "#A2A5AC"
set grid front linecolor rgb "white"
set yrange[0:]
set border linecolor rgb "white"
plot '$CSVFILE' using 1:$i smooth csplines with filledcurves y1=0 fillcolor rgb "#350C1A" fillstyle solid 1 title '', '$CSVFILE' using 1:$i smooth csplines with lines linewidth 2 linecolor rgb "#F80320" title ''
EOF
done

# Run single Gnuplot session
if [[ ${#PLOTFILES[@]} -gt 0 ]]; then
    gnuplot "$TEMPGP" 2>$OUTPUTDIR/gnuploterrors.log
    [[ -s $OUTPUTDIR/gnuploterrors.log ]] && echo "Gnuplot warnings/errors logged to $OUTPUTDIR/gnuploterrors.log" >&2
else
    echo "Error: No valid columns to plot" >&2
    rm "$TEMPGP"
    exit 1
fi

# Clean up Gnuplot temp file
rm "$TEMPGP"

# Combine all plots into a single squarish image and remove individual plots
if [[ ${#PLOTFILES[@]} -gt 0 ]]; then
    NUMIMAGES=${#PLOTFILES[@]}
    COLS=$(echo "sqrt($NUMIMAGES) + 0.5" | bc -l | awk '{print int($1)}')
    [[ $COLS -eq 0 ]] && COLS=1
    ROWS=$(( (NUMIMAGES + COLS - 1) / COLS ))
    OUTPUTFILENAME=BPL-$bitaxeName-Snapshot.png
    echo "Combining $NUMIMAGES plots into $OUTPUTFILENAME" >&2

    montage "${PLOTFILES[@]}" -tile ${COLS}x${ROWS} -background \#192730 -geometry 800x600+3+3 "$OUTPUTDIR/$OUTPUTFILENAME" 2>$OUTPUTDIR/montageerrors.log
    if [[ $? -ne 0 || -s $OUTPUTDIR/montageerrors.log ]]; then
        echo "Error: Failed to combine images, check $OUTPUTDIR/montageerrors.log" >&2
        exit 1
    fi

    # Remove individual plot files
    for FILE in "${PLOTFILES[@]}"; do
        rm -f "$FILE"
    done
else
    echo "No plots generated" >&2
    exit 1
fi
