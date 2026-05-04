#local filename="$1"
# Remove the extension from the file name
filenameTrunc=${1%.*}
#filenameTrunc=${filename%.*}
# Create a folder for the split files
#mkdir $filenameTrunc_split
#split -d -l 1000000 $filename #filenameTrunc_split/$filenameTrunc.
echo "Mayank"
echo "${filenameTrunc}."
