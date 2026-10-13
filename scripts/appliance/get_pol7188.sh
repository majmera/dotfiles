MGMTIP=10.249.169.60

# session delete
#curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X GET 'https://'$MGMTIP':443/api/rest/replication_session?select=id&limit=2000' |grep id |cut -b 9-44 > sessidlist


#policy delete

time curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X GET 'https://'$MGMTIP':443/api/rest/policy?select=*&limit=2000' > pollist

cat pollist
