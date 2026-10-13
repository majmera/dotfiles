MGMTIP=10.249.5.206
lunCount=200
#policy=56bbc87a-dbc6-4542-a385-2683bb182de3 #5min
policy=5b46f5b0-bcc0-4404-8395-651381510297
hostid=871481bd-aa28-40e1-9d59-62d62866f317
#lunCount=1000
lunsize=268435456000
#lunsize=107374182400
#lunsize=53687091200
#lunsize=1070596096
#lunsize=85899345920
#lunsize=41875931136 #200
#lunsize=64424509440 #128
#lunsize=274877906944
#lunsize=219043332096
#lunsize=21474836480
#lunsize=107374182400
#lunsize=53687091200
basename=A1_test1
while [ $lunCount -gt 0 ]

do
  date
  #time curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X POST -d '{"name":"'$basename'Baselun'$lunCount'","size":'$lunsize',"description":"testlun1","appliance_id":"A1"}' https://$MGMTIP:443/api/rest/volume
  time curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X POST -d '{"name":"'$basename'Baselun'$lunCount'","size":'$lunsize',"description":"testlun1","host_id":"'$hostid'","appliance_id":"A1"}' https://$MGMTIP:443/api/rest/volume
  #time curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X POST -d '{"name":"'$basename'Baselun'$lunCount'","size":'$lunsize',"description":"testlun1","protection_policy_id": "'$policy'", "appliance_id":"A3"}' https://$MGMTIP:443/api/rest/volume
  #time curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X POST -d '{"name":"'$basename'Baselun'$lunCount'","size":'$lunsize',"description":"testlun1","host_id":"'$hostid'","protection_policy_id": "'$policy'"}' https://$MGMTIP:443/api/rest/volume
  lunCount=`expr $lunCount - 1`

done
