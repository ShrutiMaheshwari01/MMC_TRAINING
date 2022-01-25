#!/bin/ksh

# ___________________________________________________________________________________ 
# ___________________________________________________________________________________ 
# |                                                                                  |
# | File Name    : TEST                                                              |
# |                                                                                  |
# |  Author                  Date          Version  Remarks                          |
# | -----------            ---------     -------  --------------------------         |
# |  Shruti Maheshwari      12-01-2021      1.0     Created                          |
# |_________________________________________________________________________________ |

# 

#  Export FORMS_PATH and other shell variables 
export FORMS_PATH=$FORMS_PATH:$AU_TOP/forms/US
APPSID=$1
CUST_ID=$2
 CHKLOGIN(){
             if sqlplus -s /nolog <<EOX >/dev/null 2>&1
# ___________________________________________________________________
# Function to Check the validity of database user and password.
# ___________________________________________________________________
 CHKLOGIN(){
             if sqlplus -s /nolog <<EOX >/dev/null 2>&1
                 WHENEVER SQLERROR EXIT 1;
                 CONNECT $1 ;
                  EXIT
EOX
             then
                   echo "OK"
             else
                  echo "NOK"
             fi
          }
 # ___________________________________________________________________
 #  Prompt for APPS Login Id /Password
 # ___________________________________________________________________
 while [ "$APPSID" = "" -o `CHKLOGIN "$APPSID"` = "NOK" ]
 do
   if [ "$APPSID" = "" ];then
          echo "___________________________________________________________________"
          echo "   Enter APPS Login Userid/Passwd : "
          echo "___________________________________________________________________"
          read APPSID
   else
          echo "___________________________________________________________________"
          echo " APPS Login UserId And Password Is Not CORRECT "
          echo "___________________________________________________________________"
          read APPSID = ""
          unset APPSID
   fi
 done

apps_user=`echo $APPSID | cut -d / -f 1 | cut -d @ -f 1`
apps_pwd=`echo $APPSID | cut -d / -f 2 | cut -d @ -f 1`
if [ "x$CONTEXT_FILE" = "x" ] ; then
    echo Error: CONTEXT_FILE environment variable not set!
    exit 1
fi

TNS_STRING=`cat $CONTEXT_FILE|grep s_apps_jdbc_connect_descriptor|cut -d"@" -f2 | sed 's/<\/jdbc_url>//'`

if [ "x$TNS_STRING" = "x" ] ; then
    echo Error: Could not parse the Context file for the TNS entry!
    exit 1
fi

# ___________________________________________________________________
# Copy zip file to the folder and unzip files                            
# ___________________________________________________________________
echo "Creating directory:TEST"
mkdir TEST
echo "Copying zip file:TEST.zip to directory TEST"
cp TEST.zip TEST
cd TEST
echo "Unzipping file:TEST.zip to directory TEST"
unzip TEST.zip 

# ___________________________________________________________________
# PL/SQL, SQL File                           
# ___________________________________________________________________
[ ! -d $MMCCUS_TOP/admin/sql ] && mkdir -p $MMCCUS_TOP/admin/sql
echo "Copying file:XXMMC_TEST_PKG.pks to $MMCCUS_TOP/admin/sql"
cp XXMMC_TEST_PKG.pks $MMCCUS_TOP/admin/sql


echo "Compiling XXMMC_TEST_PKG.pks"
sqlplus -s $APPSID @XXMMC_TEST_PKG.pks> XXMMC_TEST_PKG.pks.tmp 2>XXMMC_TEST_PKG.pks.tmp
errorcount=`grep -i error XXMMC_TEST_PKG.pks.tmp | grep -icv "No errors"`
cat XXMMC_TEST_PKG.pks.tmp

[ ! -d $MMCCUS_TOP/admin/sql ] && mkdir -p $MMCCUS_TOP/admin/sql
echo "Copying file:XXMMC_TEST_PKG.pkb to $MMCCUS_TOP/admin/sql"
cp XXMMC_TEST_PKG.pkb $MMCCUS_TOP/admin/sql


echo "Compiling XXMMC_TEST_PKG.pkb"
sqlplus -s $APPSID @XXMMC_TEST_PKG.pkb> XXMMC_TEST_PKG.pkb.tmp 2>XXMMC_TEST_PKG.pkb.tmp
errorcount=`grep -i error XXMMC_TEST_PKG.pkb.tmp | grep -icv "No errors"`
cat XXMMC_TEST_PKG.pkb.tmp
if [ "$errorcount" -ge "1" ]
then 
      migrErrorCode=1
fi
# ___________________________________________________________________
# Cleanup                           
# ___________________________________________________________________
cat *.tmp > TEST.log
#rm *.tmp  
cp *.log ../ 
          echo "___________________________________________________________________"
          echo " Emailing error log  "
          echo "___________________________________________________________________"
ATTACH_FILENAME=TEST.log 
FCP_RECIPIENTS=shruti.maheshwari@mmc.com
FCP_EMAIL_SUBJECT=TEST.log 
( echo "to:"${FCP_RECIPIENTS}                                                
  echo "from: no-reply@mmc.com"
  echo "subject:"${FCP_EMAIL_SUBJECT}                                        
  echo "mime-version: 1.0"                                                   
  echo "content-type: multipart/related; boundary=xxxRANDOMSTRINGxxx"        
  echo                                                                       
  echo "--xxxRANDOMSTRINGxxx"                                                
  echo "content-type: text/plain"                                            
  echo                                                                       
  echo ""                                                                    
  echo ${FCP_BODY}                                                           
  echo                                                                       
  echo "--xxxRANDOMSTRINGxxx"                                                
  echo "content-type: image/gif; name="${ATTACH_FILENAME}                    
  echo "content-transfer-encoding: base64"                                   
  echo                                                                       
  openssl base64 < ${ATTACH_FILENAME} ) | sendmail -t -i                     
cd ..
#rm -r  TEST
############################END OF SCRIPT############################
