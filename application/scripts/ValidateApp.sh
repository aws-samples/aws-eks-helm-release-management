#!/bin/bash
echo "Validating Helm Install"
iteration=30
hostName=""
i=1
while [ -z $hostName ]; do
  if [[ $i -ge $iteration ]]; then
    echo "Stage Failed"
    break
    exit 1
  fi
  echo "Waiting for external IP"
  hostName=$(kubectl get svc $1 --namespace $NAMESPACE --template="{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}")
  [ -z "$hostName" ] && sleep 10
  let "i+=1"
  
done
echo "Found external hostName: $hostName"
total_lb_arn=$(aws elbv2 describe-load-balancers --region $AWS_REGION|jq  '.LoadBalancers[]' )

lbsARN=`aws elbv2 describe-load-balancers --region $AWS_REGION --query "LoadBalancers[?DNSName=='$hostName'].LoadBalancerArn" --output text`

lb_targetgroup=$( aws elbv2 describe-listeners --region $AWS_REGION --load-balancer-arn "$lbsARN"| jq -r '.Listeners[].DefaultActions[].TargetGroupArn')                                                                                        
echo $lb_targetgroup
for tbs in ${lb_targetgroup[@]}
do
    echo $tbs
    cnt=1
    while [[ $cnt -le $iteration ]]; do
    healthcheck=$(aws elbv2 describe-target-health --region $AWS_REGION --target-group-arn "$tbs" | jq '.TargetHealthDescriptions[].TargetHealth.State')
    #echo $healthcheck
    echo "${healthcheck[*]}"
    if [[ " ${healthcheck[*]} " == *"healthy"* ]];then
        printf "Health of LB %-2s for TG %-2s is %-2s -- %-12s\n" "${tbs}" "$lbsARN" "$healthcheck" "PASSED"
        break
    elif [[ " ${healthcheck[*]} " == *"unhealthy"* ]];then
        printf "Health of LB %-2s for TG %-2s is %-2s -- %-12s\n" "${tbs}" "$lbsARN" "$healthcheck" "FAILED"
        exit 1
    else
        let "cnt+=1"
        sleep 10
    fi
    done

done
