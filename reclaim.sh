#!/bin/bash

#This script is to pull all projects from new regions with excluding the exception list

#Loop the regions to pull projects list

fun_projects()
{
for region in $(cat $path/mysql_hosts_non_icehouse); do
  host_ip=$(echo $region | awk '{print $1}')
  region_name=$(echo $region | awk '{print $2}')
# We pull project list in this function
project_list=$(mysql -h $host_ip -u $username -p$password -N -e "SELECT '$region_name' As Region, '$host_ip' As HostIP, project_id, sum(ram_allocated), sum(cpu_allocated), sum(ram_used), sum(cpu_used), ROUND((1-sum(ram_used) / sum(ram_allocated) ) * 100) As UnUsed_Ram_Percentage,  ROUND((1-sum(cpu_used) / sum(cpu_allocated) ) * 100) As UnUsed_cpu_Percentage
FROM (
	SELECT 	project_id,
		SUM(CASE WHEN resource='ram' THEN hard_limit ELSE 0 END) As ram_allocated,
                SUM(CASE WHEN resource='cores' THEN hard_limit ELSE 0 END) As cpu_allocated,
                0 As ram_used,
                0 As cpu_used
		FROM nova.quotas
	    	where deleted_at is NULL
                GROUP BY project_id

	        UNION

	SELECT 	project_id,
		0 As ram_allocated,
                0 As cpu_allocated,
		SUM(CASE WHEN resource='ram' THEN in_use ELSE 0 END) As ram_used,
     	 	SUM(CASE WHEN resource='cores' THEN in_use ELSE 0 END) As cpu_used
		FROM nova.quota_usages
	    	where deleted_at is NULL
                GROUP BY project_id
	     ) quota_join
GROUP BY project_id;")
  printf "$project_list" >> $path/project_data.txt
done

# Final list starts here
  for project_data in $(cat $path/project_data.txt); do
    # Current Project limits
    region_name=$(echo $project_data | awk '{print $1}')
    host_ip=$(echo $project_data | awk '{print $2}')
    ram_unused_percentage=$(echo $project_data | awk '{print $8}')
    cpu_unused_percentage=$(echo $project_data | awk '{print $9}')
    project_id=$(echo $project_data | awk '{print $3}')
    ram_allocated=$(echo $project_data | awk '{print $4}')
    cpu_allocated=$(echo $project_data | awk '{print $5}')
    ram_used=$(echo $project_data | awk '{print $6}')
    cpu_used=$(echo $project_data | awk '{print $7}')

    if [ "$ram_allocated" -gt 204800 ] && [ "$cpu_allocated" -gt 100 ]
    then
      if [ "$ram_unused_percentage" -ge 80 ] || [ "$cpu_unused_percentage" -ge 80 ]
      then
        project_name=$(mysql -h $host_ip -u $username -p$password -N -e "select name from keystone.project where id='$project_id' and enabled=1 and parent_id !='default' and parent_id is not NULL")
        # Calc new Project limits
        # Exclude Projects reported from the list
        if [ -n "$project_name" ]; then
            if [[ "${project_name,,}" != "project01" ]] && [[ "${project_name,,}" != "project02" ]]  \
            [[ "${project_name,,}" != "newproject"* ]] && [[ "${project_name,,}" != "production0"* ]]
            then
                if [ "$ram_unused_percentage" -ge 80 ] 
    		    then
            	    ram_new_allocated=$(( $ram_allocated - (( $ram_allocated - $ram_used ) * 90 / 100 ) ))
            	    ram_unused_claimed=$(( $ram_allocated - $ram_new_allocated ))
                else
	        	    ram_new_allocated=$ram_allocated
	    	        ram_unused_claimed=$(( $ram_allocated - $ram_new_allocated ))
	            fi
                if [ "$cpu_unused_percentage" -ge 80 ]
            	then
            	    cpu_new_allocated=$(( $cpu_allocated - (( $cpu_allocated - $cpu_used ) * 90 / 100 ) ))
            	    cpu_unused_claimed=$(( $cpu_allocated - $cpu_new_allocated ))
		        else
		            cpu_new_allocated=$cpu_allocated
		            cpu_unused_claimed=$(( $cpu_allocated - $cpu_new_allocated ))
	            fi
                printf "$region_name\t $project_id\t $project_name\t $ram_allocated\t $cpu_allocated\t $ram_used\t $cpu_used\t $ram_new_allocated\t $cpu_new_allocated\t $ram_unused_claimed\t $cpu_unused_claimed\t $ram_unused_percentage\t $cpu_unused_percentage\n"
            fi
         fi
      fi
    fi
  #end for loop
done 2>> /dev/null | awk '!seen[$0]++' >> $path/project_revoke_list.txt

}

fun_mail()
{
# Sending Mail to eligible users
YYYYMMDD=`date +%Y%m%d`

for team_list_a in $(cat $path/project_email.txt); do
    team_name_a=$(echo $team_list_a | awk '{print $1}')
    TOEMAIL=$(echo $team_list_a | awk '{print $2}')
    CCEMAIL="mymail@stylesyou.com";
    FREMAIL="infor@stylesyou.com";
    SUBJECT="Action Required: Unused Quota Reclamation ($team_name_a) - $YYYYMMDD";

(
echo "From: $FREMAIL "
echo "To: $TOEMAIL "
echo "Cc: $CCEMAIL "
echo "MIME-Version: 1.0"
echo "Content-Type: multipart/alternative; "
echo "Subject: $SUBJECT "
echo ""
echo "This is a MIME-encapsulated message"
echo ""
echo "Content-Type: text/html"
echo ""
echo "<html>
<body>
<p>Dear Valued Customer,</p>
<p>As you may be aware, we&rsquo;ve reached an efficiency low in our cloud platforms. This is caused by a combination of capacity over provisioning and underutilized resources.</p>
<p>Per the table below, please note your new quota allocation in the far-right column.&nbsp;</p>

<table border="1" width="722">
<tbody>
<tr>
  <td width="182"> <p>Tenant Name:</p> </td>
  <td colspan="6" width="540"> <p>$team_name_a</p> </td>
</tr>
<tr>
  <td rowspan="2" width="182"> <p>Regions</p> </td>
  <td colspan="2" width="180"> <p>Current Quota</p> </td>
  <td colspan="2" width="180"> <p>Current Utilization</p> </td>
  <td colspan="2" width="180"> <p>New Quota</p> </td>
</tr>
<tr>
  <td width="90"> <p>RAM (MB)</p> </td>
  <td width="90"> <p>vCPU</p> </td>
  <td width="90"> <p>RAM (MB)</p> </td>
  <td width="90"> <p>vCPU</p> </td>
  <td width="90"> <p>RAM (MB)</p> </td>
  <td width="90"> <p>vCPU</p> </td>
</tr>"

for team_list_b in $(cat $path/project_revoke_list.txt); do
  team_name_b=$(echo $team_list_b | awk '{print $3}')
  if [ "$team_name_a" = "$team_name_b" ]
  then
  echo "
  <tr>
    <td width="182"> <p> $(echo $team_list_b | awk '{print $1}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $4}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $5}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $6}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $7}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $8}') </p> </td>
    <td width="90"> <p> $(echo $team_list_b | awk '{print $9}') </p> </td>
  </tr>"
 fi
done
echo "
</tbody>
</table>
<p>*Please note if no response is received&nbsp;<strong>within 2 business days of this email correspondence</strong>, we will execute the new quota allocations per the table above.</p>
<p>If you feel that this new allocation creates an issue for your near-term needs, please complete the table below and reply to this email with the Subject:&nbsp;<strong><em>Business Justification for Quota Retention.&nbsp;&nbsp;</em></strong>A member of the Cloud Services Team will reach out to you.</p>

<table border="1">
<tbody>
<tr>
  <td width="160"> <p>Tenant Owner Name</p> </td>
  <td width="563"> <p>Business Justification</p> </td>
</tr>
<tr>
  <td width="160"> <p>&nbsp;$team_name_a</p> </td>
  <td width="563"> <p>&nbsp;We need this quota for adding and expanding our shared services</p> </td>
</tr>
</tbody>
</table>

<p>Thank you in advance for your time and effort!</p>

<p>Respectfully,</p>
<p>Cloud Services Team</p>
</body>
</html>"
) > $path/mail/mail_$team_name_a.html
#) | sendmail -t

done
}

fun_pull_email()
{
  #In this Function we pull email address
  my_user=$(cat $path/.username)
  my_pass=$(cat $path/.password)
  for team in $(cat $path/project_revoke_list.txt); do
      t_name=$(echo $team | awk '{print $3}')
      t_email="distro@stylesyou.com" 
      # Curl LDAP server and get email address
      printf "$t_name\t $t_email\n"
  done 2>> /dev/null | awk '!seen[$0]++' >> $path/project_email.txt

}

#main Program
echo "`date`: Fetching NON-Icehouse Projects List"
YYYYMMDD=`date +%Y%m%d`

path=$(echo $PWD)
IFS=$'\n'
username="capacity"
password="password"
> $path/project_data.txt
> $path/project_revoke_list.txt
> $path/project_email.txt

# Calling Function for each region
fun_projects
#mail the users
echo "`date`: Pulling Email address"
fun_pull_email
echo "`date`: Sendig Mail to Users"
fun_mail
#print to csv file
awk 'BEGIN{ OFS=","; print "region_name,project_id,project_name,ram_allocated, cpu_allocated, ram_used, cpu_used, ram_new_allocated, cpu_new_allocated,ram_unused_claimed,cpu_unused_claimed,ram_unused_percentage,cpu_unused_percentage "}; NR > 0{print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13;}' $path/project_revoke_list.txt > $path/data/project_revoke_list_$YYYYMMDD.csv
# Sending attachment Email to OpenStack Admin Team
echo "`date`: Sending Attachment mail to Admin Team"
bash $path/mail_reclaim.sh
echo "`date` Completed"
