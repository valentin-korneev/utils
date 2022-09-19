echo
UPG_EXECUTABLE=`grep -il "sqlplus.*@" *.sh`
if [ $UPG_EXECUTABLE ]
then
  UPG_NAME=${UPG_EXECUTABLE:0:${#UPG_EXECUTABLE}-3}
  tar --create --file $UPG_NAME.tar --owner=oracle --group=dba --mode=+r+x *.sh
  tar --append --file $UPG_NAME.tar --owner=oracle --group=dba --mode=+r `find -maxdepth 1 -type f|grep -Ev "\.(log|gz|tar|sh)$"|gawk '{print substr($0,3)}'`
  tar --append --file $UPG_NAME.tar --owner=oracle --group=dba --mode=+r `find Plugin -type f`
  gzip -9v $UPG_NAME.tar
  icacls $UPG_NAME.tar.gz /reset /Q  >/dev/null
fi
