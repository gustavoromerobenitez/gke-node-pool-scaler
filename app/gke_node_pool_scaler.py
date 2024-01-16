#!/usr/bin/python3

import random
import time
import sys
import os
import re
import calendar
from datetime import datetime
from datetime import timedelta

from google.protobuf.timestamp_pb2 import Timestamp
from google.protobuf.duration_pb2 import Duration

from google.cloud import container_v1

class OperationModes:
    OPERATION_MODE_SCALE_UP = "SCALE_UP"
    OPERATION_MODE_SCALE_DOWN = "SCALE_DOWN"

ALL_OPERATION_MODES = [ OperationModes.OPERATION_MODE_SCALE_UP, OperationModes.OPERATION_MODE_SCALE_DOWN ]

REQUIRED_ENVIRONMENT_VARIABLES = {

    # "COMMON": [ "GOOGLE_APPLICATION_CREDENTIALS", "PROJECT_ID", "CLUSTER", "OPERATION_MODE", "LOCATION", "NODEPOOL", "DEBUG", "PAUSE_BETWEEN_OPERATIONS" ],
    "COMMON": [ "PROJECT_ID", "CLUSTER", "OPERATION_MODE", "LOCATION", "NODEPOOL", "DEBUG", "PAUSE_BETWEEN_OPERATIONS" ],
    
    OperationModes.OPERATION_MODE_SCALE_UP: [],

    OperationModes.OPERATION_MODE_SCALE_DOWN: []
}


########################################################################
#
# Checks that all required environment variables are set
#
def check_environment_variables ():

    missing = []
    
    for env_var in REQUIRED_ENVIRONMENT_VARIABLES[ "COMMON" ]:

        if os.environ.get(env_var) is None:
            missing.append(env_var)

    for env_var in REQUIRED_ENVIRONMENT_VARIABLES[ os.environ["OPERATION_MODE"] ]:

        if os.environ.get(env_var) is None:
            missing.append(env_var)
    
    if missing != []:

        print("[FATAL]", file=sys.stderr)
        print(f"[FATAL] The following environment variables have not been set and are required:", file=sys.stderr)
        print(f"[FATAL]  {missing}" , file=sys.stderr)
        print("[FATAL]", file=sys.stderr)
        return False

    return True


#
# Waits for a container_v1.types.Operation to finish
#  https://cloud.google.com/python/docs/reference/container/latest/google.cloud.container_v1.types.Operation
#
def wait_for_operation ( project_id, location, operation, debug = False, sleep_time = 5):

    not debug or print(f"[DEBUG] Operation: {operation}", file=sys.stderr)

    while operation.status != container_v1.types.Operation.Status.DONE and \
            operation.status != container_v1.types.Operation.Status.ABORTING:

        not debug or print(f"[DEBUG] Operation Current Status: {container_v1.types.Operation.Status(operation.status).name}", file=sys.stderr)

        time.sleep(sleep_time)
        operation_request = container_v1.GetOperationRequest(name=f"projects/{project_id}/locations/{location}/operations/{operation.name}")
        operation = gke_client.get_operation(request=operation_request)

    if operation.status != container_v1.types.Operation.Status.ABORTING :
        return True
    else:
        print("[ERROR]")
        print(f"[ERROR] Operation Aborted: {container_v1.types.Operation.Status(operation.status).name} - Error: {operation.error}", file=sys.stderr)
        print("[ERROR]")
        return False


########################################################################
#
# MAIN
#
if __name__ == "__main__":

    check_environment_variables() or sys.exit(1)

    # Try without Service Account Key
    # json_credentials_path = os.environ["GOOGLE_APPLICATION_CREDENTIALS"]

    project_id = os.environ["PROJECT_ID"]
    location = os.environ["LOCATION"]
    cluster = os.environ["CLUSTER"]
    operation_mode = os.environ["OPERATION_MODE"]
    nodepool = os.environ["NODEPOOL"]
    debug = os.environ["DEBUG"].lower() in ['true',1,'yes','y']
    pause_between_operations = int(os.environ["PAUSE_BETWEEN_OPERATIONS"])

    print("[INFO] ===============================================")
    print(f"[INFO] PROJECT_ID: {project_id}")
    print(f"[INFO] LOCATION: {location}")
    print(f"[INFO] CLUSTER: {cluster}")
    print(f"[INFO] OPERATION_MODE: {operation_mode}")
    print(f"[INFO] PAUSE_BETWEEN_OPERATIONS: {pause_between_operations}")
        
    # https://cloud.google.com/python/docs/reference/container/latest/google.cloud.container_v1.services.cluster_manager.ClusterManagerClient
    # gke_client = container_v1.ClusterManagerClient().from_service_account_json( json_credentials_path)
    
    # If workload identity is correctly configured, this should work
    gke_client = container_v1.ClusterManagerClient()

    scaling_config = [ scaling_option.strip() for scaling_option in re.split("\\|+", nodepool)]
    nodepool_name = scaling_config[0]
    location_policy = scaling_config[1]
    scale_down_target_nodes = scaling_config[2] # With Autoscaler disabled. This could be 0 or greater
    scale_up_min_nodes = scaling_config[3] # The min_node_count (per zone with location_policy: BALANCED) or the total_min_node_count(location_policy: ANY)
    scale_up_max_nodes = scaling_config[4] # The max_node_count (per zone with location_policy: BALANCED) or the total_max_node_count(location_policy: ANY)

    print("[INFO]")
    print("[INFO] ==========================================================")
    print(f"[INFO] NODE POOL: {nodepool_name}")
    print(f"[INFO] LOCATION_POLICY: {location_policy}")
    print(f"[INFO] SCALE_DOWN_TARGET_NODES: {scale_down_target_nodes}")
    print(f"[INFO] SCALE_UP_MIN_NODES: {scale_up_min_nodes}")
    print(f"[INFO] SCALE_UP_MAX_NODES: {scale_up_max_nodes}")
    print("[INFO]")

    match (operation_mode):

        case OperationModes.OPERATION_MODE_SCALE_UP:
            
            print(f"[INFO] Nodepool {nodepool_name} will be scaled UP")
            
            # Enable the Autoscaler for the NodePool
            # https://cloud.google.com/python/docs/reference/container/latest/google.cloud.container_v1.types.SetNodePoolAutoscalingRequest
            #location_policy_object = container_v1.types.NodePoolAutoscaling.LocationPolicy(location_policy)
            autoscaling_object = None
            match location_policy:

                case container_v1.types.NodePoolAutoscaling.LocationPolicy.BALANCED.name:
                    autoscaling_object = container_v1.types.NodePoolAutoscaling( enabled = True, location_policy = container_v1.types.NodePoolAutoscaling.LocationPolicy.BALANCED, 
                                                                            min_node_count = int(scale_up_min_nodes), max_node_count = int(scale_up_max_nodes)  )

                case container_v1.types.NodePoolAutoscaling.LocationPolicy.ANY.name:
                    autoscaling_object = container_v1.types.NodePoolAutoscaling( enabled = True, location_policy = container_v1.types.NodePoolAutoscaling.LocationPolicy.ANY, 
                                                                                    total_min_node_count = int(scale_up_min_nodes), total_max_node_count = int(scale_up_max_nodes) ) 

            autoscaling_request = container_v1.types.SetNodePoolAutoscalingRequest( name = f"projects/{project_id}/locations/{location}/clusters/{cluster}/nodePools/{nodepool_name}", 
                                                                                    autoscaling = autoscaling_object )

            try:

                operation = gke_client.set_node_pool_autoscaling ( request = autoscaling_request )
                if wait_for_operation ( project_id, location, operation):
                    print("[INFO]")
                    print(f"[INFO] Successfully ENABLED Autoscaling for NodePool {nodepool_name} with min nodes:{scale_up_min_nodes} and max nodes:{scale_up_max_nodes} and location policy: {location_policy}")
                    print(f"[INFO] The Autoscaler will now Scale UP the Node Pool {nodepool_name} to a minimum of {scale_up_min_nodes} nodes. (This may take several minutes depending on the node pool size).")
                    print("[INFO]")

            except Exception as e:
                    print("[ERROR]", file=sys.stderr)
                    print(f"[ERROR] Failed to ENABLE Autoscaling for nodepool {nodepool_name}: {e}", file=sys.stderr)
                    print("[ERROR]", file=sys.stderr)


        case OperationModes.OPERATION_MODE_SCALE_DOWN:
            
            print(f"[INFO] Nodepool {nodepool_name} will be scaled DOWN to {scale_down_target_nodes}")

            # Disable the Autoscaler for the NodePool
            # https://cloud.google.com/python/docs/reference/container/latest/google.cloud.container_v1.types.SetNodePoolAutoscalingRequest
            autoscaling_object = container_v1.types.NodePoolAutoscaling( enabled = False ) 
            autoscaling_request = container_v1.types.SetNodePoolAutoscalingRequest( name = f"projects/{project_id}/locations/{location}/clusters/{cluster}/nodePools/{nodepool_name}", 
                                                                                    autoscaling = autoscaling_object )
            try:
            
                operation = gke_client.set_node_pool_autoscaling ( request = autoscaling_request )
            
                if wait_for_operation ( project_id, location, operation, debug):
                    print("[INFO]")
                    print(f"[INFO] Successfully DISABLED Autoscaling for NodePool {nodepool_name}")

                    print(f"[INFO] Waiting {pause_between_operations} seconds to allow the configuration to take effect")
                    time.sleep(pause_between_operations)

                    print(f"[INFO] Scaling DOWN the Node Pool {nodepool_name} to {scale_down_target_nodes} (This may take several minutes depending on the node pool size)...")
                    
                    nodepool_size_request = container_v1.SetNodePoolSizeRequest(    name = f"projects/{project_id}/locations/{location}/clusters/{cluster}/nodePools/{nodepool_name}",
                                                                                    node_count = int(scale_down_target_nodes) )

                    try:
                        
                        operation = gke_client.set_node_pool_size ( request = nodepool_size_request )
                        
                        if wait_for_operation ( project_id, location, operation, debug):
                            print("[INFO]")
                            print(f"[INFO] The Node Pool {nodepool_name} has been scaled DOWN to {scale_down_target_nodes} Nodes")
                            print("[INFO]")

                    except Exception as e:
                        print("[ERROR]", file=sys.stderr)
                        print(f"[ERROR] Failed to scale DOWN the nodepool {nodepool_name}: {e}", file=sys.stderr)
                        print("[ERROR]", file=sys.stderr)

            except Exception as e:
                    print("[ERROR]", file=sys.stderr)
                    print(f"[ERROR] Failed to DISABLE Autoscaling for nodepool {nodepool_name}: {e}", file=sys.stderr)
                    print("[ERROR]", file=sys.stderr)
                

    sys.exit(0)
