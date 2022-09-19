WRAP_COMMAND=wrap
WRAP_ERRORS=$TEMP/wrap_errors
WRAP_LOG=$TEMP/wrap_log
declare -i CNT;  CNT=0
declare -i CNT_UP_TO_DATE; CNT_UP_TO_DATE=0

do_wrap () {
SRC=$1
WRP=$WRAP_PATH/$SRC.pbl
if [ "$SRC" -nt "$WRP" ]
then
  $WRAP_COMMAND iname="$SRC" oname="$WRP" 2>$WRAP_ERRORS
  if [ -s $WRAP_ERRORS ]
  then
    echo Wrap Errors!
    exit
  fi
  echo ====
  CNT+=1
else
  CNT_UP_TO_DATE+=1
fi
}

export NLS_LANG=AMERICAN_AMERICA.CL8MSWIN1251

if [ "$2" ]
then
  WRAP_PATH=$2
else
  if [ -d Linux ]
  then
    WRAP_PATH=Linux
  elif [ -d Wrap ]
  then
    WRAP_PATH=Wrap
  else
    echo No Linux or Wrap directory exists!
    exit
  fi
fi

echo

if [ $3 ]
then
  for file_name in `cat $3`
  do
    do_wrap $file_name
  done
elif [ $1 ]
then
  do_wrap "$1"
else
  shopt -s extglob
  for file_name in `ls *(*.bdy|*.pkg|*.prc|*.fnc)`
  do
    do_wrap $file_name
  done
fi

rm $WRAP_ERRORS 2>/dev/null
rm $WRAP_LOG    2>/dev/null

echo
echo "OK. Wrapped $CNT file(s). $CNT_UP_TO_DATE file(s) is up to date"

grep --directories=skip --text TODO *
