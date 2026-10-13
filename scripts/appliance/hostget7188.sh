#MGMTIP=10.225.193.72
#MGMTIP=10.225.193.72
MGMTIP=10.249.5.206
#MGMTIP=10.244.141.126 # H0117
curl -H "Content-Type: application/json" -H "cache-control: nocache" -u 'admin:Password123!' -k -X GET 'https://'$MGMTIP':443/api/rest/host?select=*&limit=2000' |python -mjson.tool
