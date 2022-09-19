declare -i MISSING;  MISSING=0


validate_script () {
declare DIR
echo -n "."
if [ -f $1 ]
then
  if [ "$FILES" ]
  then
    FILES="$FILES $1"
  else
    FILES=$1
  fi
  if [[ $1 =~ "\\" ]]
  then
    DIR="${1%\\*}\\"
  fi
  for script in `grep -iE "^@" $1|grep -ihEo "@[a-zA-Z_0-9.#\/]+"|grep -oE "[^@]+"`
  do
    validate_script $DIR$script
  done
  for script in `grep -iE "^@@RunPlugin.utl" $1|gawk '{print $2}'`
  do
    validate_script 'Plugin/'$script
  done
else
  MISSING_FILES="$MISSING_FILES $1"
  MISSING+=1
fi
}

validate_main_script () {
echo "Main script: $1"
validate_script $1

echo
sed 's/ /\n/g' <<< $FILES | gawk '{s[$0]=s[$0]+1}END{print "Scanned files: "length(s); for(i in s) if (s[i]>1) print "Warning: "i" called "s[i]" times."}'

if [ $MISSING -ne 0 ]
then
  echo
  echo "Error: $MISSING file(s) missed:"
  for f in $MISSING_FILES
  do
    echo "  $f"
  done
fi

declare -i ORPHANED;  ORPHANED=0
shopt -s extglob
ORPHANS=`find Plugin -type f 2>/dev/null`
ORPHANS="$ORPHANS `ls *(*.sql|*.trg|*.rol|*.seq|*.upg|*.utl|*.bdy|*.pkg|*.fnc|*.prc|*.vie|*.tbl|*.spb|*.sps|*.typ|*.pbl|*.mv)`"
for file in $ORPHANS
do
  if [[ ! " "$FILES" " =~ " "$file" " ]]
  then
    ORPHANED+=1
    if [ $ORPHANED -eq 1 ]
    then
      echo
      echo "Warning: The following files are not referenced:"
    fi
    if [ $ORPHANED -le 10 ]
    then
      echo "  $file"
    fi
  fi
done
if [ $ORPHANED -gt 10 ]
then
  echo "  ... total "$ORPHANED" files are not referenced!"
fi
echo
}


echo
if [ $1 ]
then
  validate_main_script $1
else
  main=`grep -il "sqlplus.*@" *.sh`
  if [[ $main =~ ^[^[:space:]]+$ ]]
  then
    script=${main/%\.sh/.sql}
    if [ ! -e $script ]
    then
      script=${main/%\.sh/.upg}
    fi
    if [ ! -e $script ]
    then
      echo "Guessed main script $script not found!"
      exit
    fi
    echo "Guessing main script from $main: $script"
    validate_main_script $script
    exit
  fi
  shopt -s extglob
  for file in `ls _+([0-9]).upg`
  do
    if [ $script ]
    then
      echo "Cannot guess from too many patch scripts: $script, $file ..."
      exit
    else
      script=$file
    fi
  done
  if [ $script ]
  then
    echo "Guessing patch script: $script"
    validate_main_script $script
  else
    echo "Main script *.sh not found!"
  fi
fi
