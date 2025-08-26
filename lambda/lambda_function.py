import json
import os
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ.get("TABLE_NAME", "vpcs")
table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event, context):
    try:
        method = event.get("requestContext", {}).get("http", {}).get("method", "POST")
        logger.info(f"HTTP method: {method}")

        if method == "GET":
            query_params = event.get("queryStringParameters") or {}
            vpc_id = query_params.get("vpc_id")
            logger.info(f"GET request for vpc_id: {vpc_id}")

            if vpc_id:
                response = table.get_item(Key={"vpc_id": vpc_id})
                item = response.get("Item")
                if not item:
                    logger.warning(f"VPC {vpc_id} not found.")
                    return {
                        "statusCode": 404,
                        "body": json.dumps({"error": f"VPC {vpc_id} not found"}),
                    }
                logger.info(f"VPC found: {item}")
                return {"statusCode": 200, "body": json.dumps(item)}
            else:
                response = table.scan()
                items = response.get("Items", [])
                logger.info(f"Listing all VPCs: {items}")
                return {"statusCode": 200, "body": json.dumps({"vpcs": items})}

        elif method == "POST":
            body = json.loads(event.get("body", "{}"))
            logger.info(f"POST body: {body}")

            vpc_cidr = body.get("vpc_cidr")
            vpc_tags = body.get("vpc_tags", [])
            subnets = body.get("subnets", [])

            if not vpc_cidr or not subnets:
                logger.error("Missing vpc_cidr or subnets in request body.")
                return {
                    "statusCode": 400,
                    "body": json.dumps({"error": "vpc_cidr and subnets are required"}),
                }

            existing = table.scan(
                FilterExpression="vpc_cidr = :cidr",
                ExpressionAttributeValues={":cidr": vpc_cidr},
            ).get("Items")
            if existing:
                logger.warning(f"VPC with CIDR {vpc_cidr} already exists.")
                return {
                    "statusCode": 400,
                    "body": json.dumps(
                        {"error": f"VPC with CIDR {vpc_cidr} already exists"}
                    ),
                }

            vpc_response = ec2.create_vpc(
                CidrBlock=vpc_cidr,
                TagSpecifications=[{"ResourceType": "vpc", "Tags": vpc_tags}],
            )
            vpc_id_created = vpc_response["Vpc"]["VpcId"]
            logger.info(f"Created VPC: {vpc_id_created}")

            subnet_ids = []
            for subnet in subnets:
                subnet_response = ec2.create_subnet(
                    VpcId=vpc_id_created,
                    CidrBlock=subnet["cidr"],
                    AvailabilityZone=subnet.get("az"),
                    TagSpecifications=[
                        {"ResourceType": "subnet", "Tags": subnet.get("tags", [])}
                    ],
                )
                subnet_id = subnet_response["Subnet"]["SubnetId"]
                subnet_ids.append(subnet_id)
                logger.info(f"Created subnet: {subnet_id}")

            table.put_item(
                Item={
                    "vpc_id": vpc_id_created,
                    "vpc_cidr": vpc_cidr,
                    "subnet_ids": subnet_ids,
                    "tags": vpc_tags,
                    "subnets": subnets,
                    "created_at": datetime.utcnow().isoformat(),
                }
            )
            logger.info(f"Saved VPC metadata to DynamoDB for VPC {vpc_id_created}")

            return {
                "statusCode": 200,
                "body": json.dumps(
                    {"vpc_id": vpc_id_created, "subnet_ids": subnet_ids}
                ),
            }

        elif method == "DELETE":
            query_params = event.get("queryStringParameters") or {}
            vpc_id = query_params.get("vpc_id")
            logger.info(f"DELETE request for vpc_id: {vpc_id}")

            if vpc_id:
                response = table.get_item(Key={"vpc_id": vpc_id})
                item = response.get("Item")
                if not item:
                    logger.warning(f"VPC {vpc_id} not found for deletion.")
                    return {
                        "statusCode": 404,
                        "body": json.dumps({"error": f"VPC {vpc_id} not found"}),
                    }

                for subnet_id in item.get("subnet_ids", []):
                    ec2.delete_subnet(SubnetId=subnet_id)
                    logger.info(f"Deleted subnet: {subnet_id}")
                ec2.delete_vpc(VpcId=vpc_id)
                logger.info(f"Deleted VPC: {vpc_id}")
                table.delete_item(Key={"vpc_id": vpc_id})
                logger.info(f"Deleted VPC metadata from DynamoDB for VPC {vpc_id}")

                return {
                    "statusCode": 200,
                    "body": json.dumps(
                        {"message": f"VPC {vpc_id} and its subnets deleted"}
                    ),
                }

            else:
                scan = table.scan()
                items = scan.get("Items", [])
                logger.info(f"Deleting all VPCs: {items}")
                for item in items:
                    for subnet_id in item.get("subnet_ids", []):
                        ec2.delete_subnet(SubnetId=subnet_id)
                        logger.info(f"Deleted subnet: {subnet_id}")
                    ec2.delete_vpc(VpcId=item["vpc_id"])
                    logger.info(f"Deleted VPC: {item['vpc_id']}")
                    table.delete_item(Key={"vpc_id": item["vpc_id"]})
                    logger.info(
                        f"Deleted VPC metadata from DynamoDB for VPC {item['vpc_id']}"
                    )

                return {
                    "statusCode": 200,
                    "body": json.dumps({"message": "All VPCs and subnets deleted"}),
                }

    except Exception as e:
        logger.error(f"Exception occurred: {str(e)}", exc_info=True)
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}
