#!/bin/bash
#path=`dirname $0`
#cd "${path}"
echo $0
echo $*
echo "重签名开始"
#ipa路径
ipaFileUrl=''
# 源文件的备份
tempPath='temp'
#目标路径
targetAppPath='targetAppPath'
#工程生成的APP包的路径
products_dir='buildFiles';
#ipa的名字
ipaName=''
#解压后app的名字
appName=''
#目标bundleid
bundleIdetifier=''
#描述文件
mobileprovisionUrl=''
#签名文件
codeSignIdentity=''
#最后的ipa路径
successIpaPath='successIpaPath'
#p12文件的路径
p12fileUrl=''
#P12的密码
p12Pwd=''
while getopts "i:b:m:f:p:" opt 
do
	case $opt in
		i )
			echo $OPTARG;
			ipaFileUrl=$OPTARG;
			echo "参数i的位置$OPTIND";;
		b )
			echo $OPTARG;
			bundleIdetifier=$OPTARG;
			echo "参数b的位置$OPTIND";; 	
		m )
			echo $OPTARG;
			mobileprovisionUrl=$OPTARG;
			echo "参数m的位置$OPTIND";; 
		f )
			echo $OPTARG;
			p12fileUrl=$OPTARG;
			echo "参数f的位置$OPTIND";; 
		p )
			echo $OPTARG;
			p12Pwd=$OPTARG;
			echo "参数p的位置$OPTIND";; 			

		? )
				echo "error" ;                   
				exit 1;;	
	esac
done
if [[ ! -n $ipaFileUrl ]]; then
	echo "请输入ipa文件的路径"
	exit 1;
fi
if [[ ! -n $bundleIdetifier ]]; then
	echo "请输入目标的bundleid"
	exit 1;
fi
if [[ ! -n $mobileprovisionUrl ]]; then
	echo "请输入目标的描述文件"
	exit 1;
fi
if [[ ! -n $p12fileUrl ]]; then
	echo "请输入目标的发布证书p12文件"
	exit 1;
fi
#1.新建文件夹
rm -rf $tempPath
mkdir -p $tempPath
rm -rf $successIpaPath
mkdir -p $successIpaPath
rm -rf "$products_dir"
mkdir -p "$products_dir"
# #----------------------------------------
# # 3. 解压IPA到Temp下
cp -rf $ipaFileUrl $tempPath
for fileName in $(ls $tempPath)
do
	ipaName=$fileName
done
echo "ipa的名字=$ipaName"
unzip -oqq "$ipaFileUrl" -d "$tempPath"
# # 拿到解压的临时的APP的路径
tempAppPath=$(set -- "$tempPath/Payload/"*.app;echo "$1")
echo "路径是:$tempAppPath"
for fileName in $(ls $tempPath/Payload/) 
do
	appName=$fileName
done
echo "名字是:$appName"
#----------------------------------------
# 4. 将解压出来的.app拷贝进入工程下
cp -rf "$tempPath/" "$products_dir/"
targetAppPath="$products_dir/Payload/$appName"
#----------------------------------------
# 5. 删除extension和WatchAPP.个人证书没法签名Extention
rm -rf "$targetAppPath/PlugIns"
rm -rf "$targetAppPath/Watch"



#----------------------------------------
# 6. 复制出来temp.plist
#  
/usr/bin/security cms -D -i ${mobileprovisionUrl} > $products_dir/temp.plist

#----------------------------------------
# 7. mobileprovision中的embedded.mobileprovision是否等于bundleIdetifier
#并生成复制出来entitlements.plist
#  
plistName=$products_dir/temp.plist
teamIdentifier=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' $plistName)
provisioningProfile=$(/usr/libexec/PlistBuddy -c 'Print UUID' $plistName)
applicationIdentifier=$(/usr/libexec/PlistBuddy -c 'Print Entitlements:application-identifier' $plistName)
entitlements=$(/usr/libexec/PlistBuddy -x -c 'Print Entitlements' $plistName)
echo "teamIdentifier==$teamIdentifier"
echo "provisioningProfile==$provisioningProfile"
echo "applicationIdentifier==$applicationIdentifier"
# echo "entitlements===$entitlements"
if [[ $applicationIdentifier != *$bundleIdetifier ]]; then
	echo "目标bundleid和描述文件不匹配";
	exit 1;
fi
echo $entitlements > $products_dir/entitlements.plist

#----------------------------------------
# 8. 导入p12文件，并获取签名信息
# 
/usr/bin/security import $p12fileUrl -P "$p12Pwd"
codesings=`/usr/bin/security find-identity -v -p codesigning|grep $teamIdentifier`
echo  $codesings
codeSignIdentity=${codesings#*\"}
codeSignIdentity=${codeSignIdentity%\"}
echo $codeSignIdentity
# 9. 移除 embedded.mobileprovision,并复制mobilepr"vision "embedded.mobileprovision
#这里是强制复制
# 
cp -rf ${mobileprovisionUrl} $targetAppPath/embedded.mobileprovision

#----------------------------------------
# 10. 更新info.plist文件 CFBundleIdentifier
#  设置:"Set : KEY Value" "目标文件路径"
echo "$targetAppPath/Info.plist"
echo $bundleIdetifier
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $bundleIdetifier" "$targetAppPath/Info.plist"
/usr/libexec/PlistBuddy -c "delete :CFBundleResourceSpecification" "$targetAppPath/Info.plist"

# #----------------------------------------
# 11. 重签名第三方 FrameWorks
TARGET_APP_FRAMEWORKS_PATH="$targetAppPath/Frameworks"
if [ -d "$TARGET_APP_FRAMEWORKS_PATH" ];
then
for FRAMEWORK in "$TARGET_APP_FRAMEWORKS_PATH/"*
do
#签名
/usr/bin/codesign -fs "$codeSignIdentity" --no-strict --entitlements=$products_dir/entitlements.plist $FRAMEWORK
done
fi
# 12.签名整个app
/usr/bin/codesign -fs "$codeSignIdentity" --no-strict --entitlements=$products_dir/entitlements.plist $targetAppPath
##13. 压缩生成ipa包
cd $products_dir
zip -qry resign-$ipaName Payload
cd ..
cp -rf $products_dir/resign-$ipaName $successIpaPath/resign-$ipaName
echo "创建成功路径为===$products_dir/resign-$ipaName"

