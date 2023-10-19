#!/bin/bash

OIFS="$IFS"
IFS=$'\n'

rootPath=$(pwd)
org=$(jq -r '.organization' $rootPath/config.json)
env=$(jq -r '.environment' $rootPath/config.json)
usr=$(jq -r '.username' $rootPath/config.json)
psw=$(jq -r '.password' $rootPath/config.json)
msUrl=$(jq -r '.mgmtServer' $rootPath/config.json)
auth=`echo -n "$usr:$psw" | base64`

referenceDataFile()
{
    path=reports/references/referenceData-$org-$env.csv
    header=ORGANIZATION,ENVIRONMENT,REFERENCE,REFERS,RESOURCETYPE
    csvReport $header $path
}

keystoreDataFile()
{
    path=reports/privatekeys/privateKeyData-$org-$env.csv
    header=ORGANIZATION,ENVIRONMENT,KEYSTORE,CERT,KEY,ALIAS-NAME,ALIAS-CERT,ALIAS-KEY,EXPIRATIONDATE
    csvReport $header $path
}

targetServerDataFile()
{
    path=reports/targetservers/targetServerData-$org-$env.csv
    header=ORGANIZATION,ENVIRONMENT,SERVERNAME,HOST,ENABLED,CLIENTAUTHENABLED,KEYSTORE,KEYALIAS,TRUSTSTORE
    csvReport $header $path
}

proxyDataFile()
{
    path=reports/proxies/proxyData-$org-$env.csv
    header=ORGANIZATION,ENVIRONMENT,PROXY,REVISION,DEPLOYED,SOURCE,SOURCENAME,KEYSTORE,KEYALIAS,TRUSTSTORE
    csvReport $header $path
}

csvReport()
{
    # csvReport - path
    folder=$(echo ${2} | cut -d '/' -f 1)
    typefolder=$(echo ${2} | cut -d '/' -f 2)
    file=$(echo ${2} | cut -d '/' -f 3)

    # if not exists create reports folder
    if [ ! -d ${rootPath}/${folder}/${typefolder} ]
    then
        mkdir -p "${rootPath}/${folder}/${typefolder}" > /dev/null 2>&1 && echo "Directory $folder/${typefolder} created."
    fi

    # Create csv file
    if [ ! -f ${rootPath}/${folder}/${typefolder}/${file} ]
    then
        touch ${rootPath}/${folder}/${typefolder}/${file}
    fi

    # Write header on csv file
    if [ -f ${rootPath}/${folder}/${typefolder}/${file} ]
    then
        echo $1 > ${rootPath}/${folder}/${typefolder}/${file}
    fi

    if [ $typefolder == "references" ]; then
        reportFile=${rootPath}/reports/${typefolder}/referenceData-$org-$env.csv
    elif [ $typefolder == "privatekeys" ]; then
        reportFile=${rootPath}/reports/${typefolder}/privateKeyData-$org-$env.csv
    elif [ $typefolder == "targetservers" ]; then
        reportFile=${rootPath}/reports/${typefolder}/targetServerData-$org-$env.csv
    elif [ $typefolder == "proxies" ]; then
        reportFile=${rootPath}/reports/${typefolder}/proxyData-$org-$env.csv
    fi

    cd $rootPath
}

csv()
{
    local items=("$@")
    for i in "${!items[@]}"
    do
        if [[ "${items[$i]}" =~ [,\"] ]]
        then
            items[$i]=\"$(echo -n "${items[$i]}" | sed s/\"/\"\"/g)\"
        fi
    done
    (
    IFS=,
    echo "${items[*]}"
    )
}

getReferenceData()
{
    referenceDataFile
    echo "Organization: $org | Environment: $env"
    echo "Processing References"

    # '******* Get all references in an Env *******'
    countReferences=0
    opdkReferences=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/references")
    countTotal=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/references" | jq length)

    # '******* Get reference details *******'
    for opdkReference in $(echo "$opdkReferences" | jq -r '.[]' | sort); do
        echo "*** opdkReference: $opdkReference"
        url=$(echo $msUrl/v1/organizations/$org/environments/$env/references/$opdkReference | sed "s/ /%20/g")
        statusCode=$(curl -H "Authorization: Basic $auth" -sS -I GET "$url" 2> /dev/null | head -n 1 | cut -d ' ' -f2)
        if [[ $statusCode != 200 ]]; then
            echo "$opdkReference | Error | HTTP Status: $statusCode"
        else
            opdkReferenceDetails=$(curl -H "Authorization: Basic $auth" -s -X GET "$url")

            opdkReferenceName=$(echo $opdkReferenceDetails | jq -r '.name')
            [ -z "$opdkReferenceName" ] && opdkReferenceName="-"
            opdkReferenceRefers=$(echo $opdkReferenceDetails | jq -r '.refers')
            [ -z "$opdkReferenceRefers" ] && opdkReferenceRefers="-"
            opdkReferenceType=$(echo $opdkReferenceDetails | jq -r '.resourceType')
            [ -z "$opdkReferenceType" ] && opdkReferenceType="-"

            csv $org $env $opdkReferenceName $opdkReferenceRefers $opdkReferenceType >> $reportFile
        fi
        countReferences=$((countReferences+1))
    done
    echo "***** Total References: $countReferences/$countTotal"
}

getKeystoreData()
{
    keystoreDataFile
    echo "Organization: $org | Environment: $env"
    echo "Processing Keystores"

    # '******* Get all keystores in an Env *******'
    countKeystores=0
    opdkKeystores=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/keystores")
    countTotal=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/keystores" | jq length)

    # '******* Get keystore details *******'
    for opdkKeystore in $(echo "$opdkKeystores" | jq -r '.[]' | sort); do
        echo "*** opdkKeystore: $opdkKeystore"
        url=$(echo $msUrl/v1/organizations/$org/environments/$env/keystores/$opdkKeystore | sed "s/ /%20/g")
        statusCode=$(curl -H "Authorization: Basic $auth" -sS -I GET "$url" 2> /dev/null | head -n 1 | cut -d ' ' -f2)
        if [[ $statusCode != 200 ]]; then
            echo "$opdkKeystore | Error | HTTP Status: $statusCode"
        else
            opdkKeystoreDetails=$(curl -H "Authorization: Basic $auth" -s -X GET "$url")

            opdkKeystoreCerts=`jq -r '.certs[]' <<< $opdkKeystoreDetails`
            opdkKeystoreCerts=$(echo $opdkKeystoreCerts | tr '\n' '|' | sed 's/.$//')
            [ -z "$opdkKeystoreCerts" ] && opdkKeystoreCerts="-"

            opdkKeystoreKeys=`jq -r '.keys[]' <<< $opdkKeystoreDetails`
            opdkKeystoreKeys=$(echo $opdkKeystoreKeys | tr '\n' '|' | sed 's/.$//')
            [ -z "$opdkKeystoreKeys" ] && opdkKeystoreKeys="-"

            if [[ $(jq -c '.aliases | length' <<< $opdkKeystoreDetails) = 0 ]]; then
                opdkKeystoreAliasName="-"
                opdkKeystoreAliasCert="-"
                opdkKeystoreAliasKey="-"
                csv $org $env $opdkKeystore $opdkKeystoreCerts $opdkKeystoreKeys $opdkKeystoreAliasName $opdkKeystoreAliasCert $opdkKeystoreAliasKey >> $reportFile
            else
                for i in $(jq -c '.aliases[]' <<< $opdkKeystoreDetails); do
                    opdkKeystoreAliasName=`jq -r '.aliasName' <<< $i`
                    [ -z "$opdkKeystoreAliasName" ] && opdkKeystoreAliasName="-"
                    opdkKeystoreAliasCert=`jq -r '.cert' <<< $i`
                    [ -z "$opdkKeystoreAliasCert" ] && opdkKeystoreAliasCert="-"
                    opdkKeystoreAliasKey=`jq -r '.key' <<< $i`
                    [ -z "$opdkKeystoreAliasKey" ] && opdkKeystoreAliasKey="-"

                    # '******* Get the alias expiration date *******'
                    url=$(echo $msUrl/v1/organizations/$org/environments/$env/keystores/$opdkKeystore/aliases/$opdkKeystoreAliasName | sed "s/ /%20/g")
                    statusCode=$(curl -H "Authorization: Basic $auth" -sS -I GET "$url" 2> /dev/null | head -n 1 | cut -d ' ' -f2)                   
                    if [[ $statusCode != 200 ]]; then
                        echo "$opdkKeystore-$opdkKeystoreAliasName | Error | HTTP Status: $statusCode"
                        opdkAliasExpiration="-"
                    else
                        opdkAliasExpiration=""
                        opdkAliasDetails=$(curl -H "Authorization: Basic $auth" -s -X GET "$url")
                        opdkAliasisValid=`jq -r '.certsInfo.certInfo[].isValid' <<< $opdkAliasDetails`
                        opdkAliasExpirationDates=`jq -r '.certsInfo.certInfo[].expiryDate' <<< $opdkAliasDetails`
                        #opdkAliasExpiration=$(echo $opdkAliasExpiration | tr '\n' '|' | sed 's/.$//') #epochformat
                        for e in $opdkAliasExpirationDates; do
                            opdkAliasExp=`date -d @$(($e/1000)) '+%m/%d/%Y:%H:%M:%S'.$(($e%1000))`
                            opdkAliasExpiration+="$opdkAliasExp"
                            opdkAliasExpiration+="|"
                        done
                        opdkAliasExpiration=$(echo $opdkAliasExpiration | sed 's/.$//')
                        echo "opdkAliasExpiration for $opdkKeystoreAliasName:" $opdkAliasExpiration
                        [ -z "$opdkAliasExpiration" ] && opdkAliasExpiration="-"
                    fi
                    csv $org $env $opdkKeystore $opdkKeystoreCerts $opdkKeystoreKeys $opdkKeystoreAliasName $opdkKeystoreAliasCert $opdkKeystoreAliasKey $opdkAliasExpiration >> $reportFile
                done
            fi
        fi
        countKeystores=$((countKeystores+1))
    done
    echo "***** Total Keystores: $countKeystores/$countTotal"
}

getTargetServerData()
{
    targetServerDataFile
    echo "Organization: $org | Environment: $env"
    echo "Processing Target Servers"

    # '******* Get all targetservers in an Env *******'
    countTargetServers=0
    opdkTargetServers=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/targetservers")
    countTotal=$(curl -H "Authorization: Basic $auth" -s -X GET "$msUrl/v1/organizations/$org/environments/$env/targetservers" | jq length)

    # '******* Get targetservers details *******'
    for opdkTargetServer in $(echo "$opdkTargetServers" | jq -r '.[]' | sort); do
        echo "*** opdkTargetServer: $opdkTargetServer"
        url=$(echo $msUrl/v1/organizations/$org/environments/$env/targetservers/$opdkTargetServer | sed "s/ /%20/g")
        statusCode=$(curl -H "Authorization: Basic $auth" -sS -I GET "$url" 2> /dev/null | head -n 1 | cut -d ' ' -f2)
        if [[ $statusCode != 200 ]]; then
            echo "$opdkTargetServer | Error | HTTP Status: $statusCode"
        else
            opdkTargetServerDetails=$(curl -H "Authorization: Basic $auth" -s -X GET "$url")

            opdkTsName=$(echo $opdkTargetServerDetails | jq -r '.name')
            [ -z "$opdkTsName" ] && opdkTsName="-"
            opdkTsHost=$(echo $opdkTargetServerDetails | jq -r '.host')
            [ -z "$opdkTsHost" ] && opdkTsHost="-"
            opdkTsEnabled=$(echo $opdkTargetServerDetails | jq -r '.isEnabled')
            [ -z "$opdkTsEnabled" ] && opdkTsEnabled="-"
            opdkTsSslClientAuthEnabled=$(echo $opdkTargetServerDetails | jq -r '.sSLInfo.clientAuthEnabled')
            [ -z "$opdkTsSslClientAuthEnabled" ] && opdkTsSslClientAuthEnabled="-"
            opdkTsSslKeystore=$(echo $opdkTargetServerDetails | jq -r '.sSLInfo.keyStore')
            [ -z "$opdkTsSslKeystore" ] && opdkTsSslKeystore="-"
            opdkTsSslKeyalias=$(echo $opdkTargetServerDetails | jq -r '.sSLInfo.keyAlias')
            [ -z "$opdkTsSslKeyalias" ] && opdkTsSslKeyalias="-"
            opdkTsSslTruststore=$(echo $opdkTargetServerDetails | jq -r '.sSLInfo.trustStore')
            [ -z "$opdkTsSslTruststore" ] && opdkTsSslTruststore="-"            

            csv $org $env $opdkTsName $opdkTsHost $opdkTsEnabled $opdkTsSslClientAuthEnabled $opdkTsSslKeystore $opdkTsSslKeyalias $opdkTsSslTruststore >> $reportFile
        fi
        countTargetServers=$((countTargetServers+1))
    done
    echo "***** Total Target Servers: $countTargetServers/$countTotal"
}

getProxiesData()
{
    proxyDataFile
    echo "Organization: $org | Environment: $env"
    echo "Processing Proxies"

    opdkRev=0
    opdkDep="N"
    opdkSrc="-"
    opdkSrcName="-"
    opdkPxKeystore="-"
    opdkPxKeyAlias="-"
    opdkPxTruststore="-"
    opdkProxy="ijvv-cxp-idomoo-proxy"
    opdkRev=8

    echo INFO: "Proxy: $opdkProxy | Revision:" $opdkRev
    purl=$(echo $msUrl/v1/organizations/$org/apis/$opdkProxy/revisions/$opdkRev/policies | sed "s/ /%20/g")
    proxyPolicies=$(curl -H "Authorization: Basic $auth" -s -X GET "$purl")
    for proxyPolicy in $(echo "$proxyPolicies" | jq -r '.[]' | sort); do
        plurl=$(echo $msUrl/v1/organizations/$org/apis/$opdkProxy/revisions/$opdkRev/policies/$proxyPolicy | sed "s/ /%20/g")
        proxyPolicyDetails=$(curl -H "Authorization: Basic $auth" -s -X GET "$plurl")
        opdkPolType=$(echo $proxyPolicyDetails | jq -r '.policyType')
        if [[ $opdkPolType == "ServiceCallout" ]]; then
            opdkSrc=$opdkPolType
            opdkSrcName=$(echo $proxyPolicyDetails | jq -r '.name')
            [ -z "$opdkSrcName" ] && opdkSrcName="-"
            opdkPxSslClientAuthEnabled=$(echo $proxyPolicyDetails | jq -r '.targetConnection.sSLInfo.clientAuthEnabled')
            [ -z "$opdkPxSslClientAuthEnabled" -o "$opdkPxSslClientAuthEnabled" == null ] && opdkPxSslClientAuthEnabled="-"
            opdkPxKeystore=$(echo $proxyPolicyDetails | jq -r '.targetConnection.sSLInfo.keyStore')
            [ -z "$opdkPxKeystore" -o "$opdkPxKeystore" == null ] && opdkPxKeystore="-"
            opdkPxKeyAlias=$(echo $proxyPolicyDetails | jq -r '.targetConnection.sSLInfo.keyAlias')
            [ -z "$opdkPxKeyAlias" -o "$opdkPxKeyAlias" == null ] && opdkPxKeyAlias="-"
            opdkPxTruststore=$(echo $proxyPolicyDetails | jq -r '.targetConnection.sSLInfo.trustStore')
            [ -z "$opdkPxTruststore" -o "$opdkPxTruststore" == null ] && opdkPxTruststore="-"

            #header=ORGANIZATION,ENVIRONMENT,PROXY,REVISION,DEPLOYED,SOURCE,SOURCENAME,KEYSTORE,KEYALIAS,TRUSTSTORE
            csv $org $env $opdkProxy $opdkRev $opdkDep $opdkSrc $opdkSrcName $opdkPxKeystore $opdkPxKeyAlias $opdkPxTruststore >> $reportFile
        fi
    done
}

# Start of script
cd $rootPath

echo 'start time:' `date`

if [[ $org = "" || $env = "" || $usr = "" || $psw = "" || $msUrl = "" ]]; then
    echo "Unable to proceed. Please revisit the config file."
    exit
elif [[ $env = *[^[a-zA-Z0-9_\-]]* ]]; then
    echo "One environment at a time only. Please revisit the config file."
    exit
else
    rm -rf ./reports
    #getKeystoreData
    #getReferenceData
    #getTargetServerData
    getProxiesData
    #getSharedflowsData
fi

echo 'end time:' `date`
IFS="$OIFS"
