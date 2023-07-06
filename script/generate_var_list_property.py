#!/usr/bin/env python3
"""
https://github.com/FreeOpcUa/python-opcua

https://github.com/FreeOpcUa/opcua-asyncio

https://github.com/FreeOpcUa/opcua-client-gui

sudo dnf install -y python39

pip3 install --user asyncua

uabrowse -u $opcua_server_url -l 0 -d 10 -p 'Objects,2:OpcPlc,2:Telemetry'

Generate overrides file for ACE application and then apply:

./generate_var_list_property.py \
    --url $opcua_server_url \
    --root 0:Objects/2:OpcPlc/2:Telemetry \
    --to $ace_host_work_directory/ua_overrides.txt \
    --flow OPCUA_data_sub \
    --node OPC-UA-Input

ibmint apply overrides $ace_container_work_directory/ua_overrides.txt --work-directory $ace_container_work_directory

Directly apply overrides to ACE application:

sudo chmod -R a+rw $ace_host_work_directory
sudo find $ace_host_work_directory -type d -print0|xargs -0 sudo chmod a+x

./generate_var_list_property.py \
    --workdir $ace_host_work_directory \
    --url $opcua_server_url \
    --root 0:Objects/2:OpcPlc/2:Telemetry \
    --to OPCTestApp \
    --flow OPCUA_data_sub \
    --node OPC-UA-Input \
    --excludes '["Special","ABCDEFGH","GUID","Anomaly"]' \
    --max 100

./generate_var_list_property.py \
    --workdir $ace_host_work_directory \
    --url $opcua_server_url \
    --root 0:Objects/2:OpcPlc/2:Telemetry \
    --to OPCTestApp \
    --flow OPCUA_data_read \
    --node OPC-UA-Read \
    --type read \
    --excludes '["Special","ABCDEFGH","GUID","Anomaly"]' \
    --max 100

    
"""

import re
import os
import json
import uuid
import asyncio
import argparse
import logging
import urllib.parse
from asyncua import Client, ua

# properties in message flow XML
PROP_SERVER = "opcUaServerList"
PROP_TRIGGER_ITEMS = "triggerItemList"
PROP_CLIENT_ITEMS = "clientItemList"

# default source uuid
SOURCE_ROOT_UUID = "00000000-0000-1000-8000-000000000002"
# Default source path
SOURCE_DEFAULT_ROOT = "/Source"
# Default client item path
CLIENT_DEFAULT_ROOT = "/Item"


async def find_all(
    parent, parent_path: str = "", result: list = [], excludes=None, max_items=None
):
    """
    Recursively find all variables under the specified parent node
    :param parent: parent node
    :param parent_path: parent path (or None for initial node)
    :param result: list of items found
    :param excludes: list of regular expressions to exclude
    :param max_items: maximum number of items to return
    :return: list of items under specified parent node with format: {"subpath": "the/sub/path", "node_id": "ns=2; the node id"}
    """
    logging.info(f"browsing {len(result)} {parent_path}")
    # browse children
    for child_node in await parent.get_children():
        # check if we have enough items
        if result and max_items and len(result) >= max_items:
            return result
        # get child attributes
        attrs = await child_node.read_attributes(
            [
                ua.AttributeIds.BrowseName,
                ua.AttributeIds.NodeId,
                ua.AttributeIds.NodeClass,
            ]
        )
        # extract attributes values
        browse_name, node_id, child_class = [attr.Value.Value for attr in attrs]
        # simplification: since we navigate a single namespace, we can ignore namespace index
        child_path = browse_name.to_string().split(":")[-1]
        # prefix with parent path if provided
        if parent_path:
            child_path = f"{parent_path}/{child_path}"
        identifier = node_id.to_string()
        if excludes is not None:
            to_exclude = False
            for test_re in excludes:
                if re.match(test_re, child_path):
                    to_exclude = True
                    break
            if to_exclude:
                logging.debug(f"excluding {child_path} : {identifier}")
                continue
        if child_class == ua.NodeClass.Variable:
            logging.debug(f"adding {len(result)} {child_path} : {identifier}")
            result.append({"subpath": child_path, "node_id": identifier})
        else:
            await find_all(
                parent=child_node,
                parent_path=child_path,
                result=result,
                excludes=excludes,
                max_items=max_items,
            )
    return result


async def get_node_list_for_path(url, selection_filter, excludes, max_items=None):
    """
    :return: list of items under the specified path using format of find_all
    """
    logging.info(f"Connecting to {url} ...")
    async with Client(url=url) as client:
        logging.info(f"Connected.")
        ua.NodeId,
        path_selection = selection_filter.split("/")
        selected_root = await client.nodes.root.get_child(path_selection)
        namespaces = await client.get_namespace_array()
        logging.info(f"Root node found: {selected_root.nodeid.to_string()}")
        all_items = await find_all(
            parent=selected_root, excludes=excludes, max_items=max_items
        )
        return {
            "namespaces": namespaces,
            "items": all_items,
            "root_ns_index": selected_root.nodeid.NamespaceIndex,
        }


def item_to_uri_params(info: dict):
    """
    Encode info dict to URI
    Args:
        info: one source or server information
    """
    suffix = ""
    if "SOURCE_ITEM_ADDR" in info:
        suffix = "|||"
    encoded_pairs = []
    for key, value in info.items():
        if isinstance(value, str):
            value = urllib.parse.quote(str(value), safe=":/;#[] *")
        else:
            value = str(value).lower()
        encoded_pairs.append(f"{key}={value}")
    return (
        f"{info['MAPPING_ID']}:{info['MAPPING_PATH']}?{'$'.join(encoded_pairs)}{suffix}"
    )


def item_list_to_property(item_list: list, prop_name: str):
    """
    Convert list of items in dict to property value string suitable for triggerItemList
    """
    src_list = []
    if prop_name == PROP_TRIGGER_ITEMS:
        src_list.append("4")
    elif prop_name == PROP_CLIENT_ITEMS:
        src_list.append("3")
    else:
        raise ValueError(f"Unknown property name {prop_name}")
    for item in item_list:
        src_list.append(item_to_uri_params(item))
    return ",".join(src_list)


def get_source_props(
    root_path: str,
    item_subpath: str,
    item_id: str,
    namespaces: list,
    namespace_int: int,
    client_item_root: str,
    prop_name: str,
):
    """
    :return: dict of source properties for one item
    Args:
        root_path: root path of source, e.g. '0:Objects/2:OpcPlc/2:Telemetry'
        item_subpath: subpath of item, e.g. 'Fast/FastDouble1'
        item_id: node id of item, e.g. 'ns=2;s=FastDouble1'
        namespaces: list of namespaces, e.g. ['http://opcfoundation.org/UA/', 'http://microsoft.com/Opc/OpcPlc/']
        namespace_int: namespace index, e.g. 2
        client_item_root: root path of client item, e.g. '/Item'
    """
    item_subpath_array = item_subpath.split("/")
    # last group in path : "Telemetry"
    root_name = root_path.split("/")[-1].split(":")[1]
    # /Objects/2:OpcPlc/2:Telemetry/2:Fast/2:FastDouble1
    source_item_path = "/".join(
        [root_path] + [f"{namespace_int}:{item}" for item in item_subpath_array]
    )
    logging.debug(f"Source item path: {source_item_path}")
    # /Item/Telemetry/Fast/FastDouble1
    mapping_path = "/".join([client_item_root, root_name] + item_subpath_array)
    logging.debug(f"Item: {mapping_path} : {item_id}")
    result = {
        "EVENT_LIST": False,
        "HAS_HISTORY": False,
        "HOLDS_VALUE": True,
        "ITEM_QUEUE_SIZE": 0,
        "MAPPING_ID": uuid.uuid4(),
        "MAPPING_PATH": mapping_path,
        "METHOD_LIST": "false",
        "SAMPLE_RATE": 0,
        "SOURCE_ITEM_ADDR": item_id,
        "SOURCE_ITEM_NS": namespaces[namespace_int],
        "SOURCE_ITEM_PATH": source_item_path,
        "SOURCE_PATH": SOURCE_DEFAULT_ROOT,
        "SOURCE_REF": SOURCE_ROOT_UUID,
        "VERSION_TIME": "2023-06-09T07:29:29.380+0000",
    }
    if prop_name == PROP_CLIENT_ITEMS:
        result["INDEX_RANGE"] = ""
    return result


def configurable_property_uri(flow_name: str, node_name: str, prop_name: str):
    """
    property name suitable for ibmint apply overrides
    """
    return f"{flow_name}#{node_name}.{prop_name}"


def override_property_line(prop_uri: str, prop_value: str):
    """
    one line of override property file suitable for ibmint apply overrides
    """
    return f"{prop_uri}={prop_value}\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", help="OPC UA server URL", type=str, required=True)
    parser.add_argument("--root", help="Root path", type=str, default=None)
    parser.add_argument(
        "--to",
        help="Output file name or Application name (with workdir)",
        type=str,
        required=True,
    )
    parser.add_argument("--flow", help="flow name", type=str, required=True)
    parser.add_argument("--node", help="node name", type=str, required=True)
    parser.add_argument(
        "--workdir",
        help="ACE workdir, set to save directly in application",
        type=str,
        default=None,
    )
    parser.add_argument("--max", help="max number of items", type=int)
    parser.add_argument(
        "--type", help="type of items", type=str, choices=["sub", "read"], default="sub"
    )
    parser.add_argument(
        "--excludes",
        help="filter JSON with regex to exclude",
        type=json.loads,
        default=None,
    )
    parser.add_argument(
        "--debug",
        help="log level, debug=10, info=20, warning=30 (default)",
        type=int,
        default=20,
    )
    args = parser.parse_args()
    logging.basicConfig(level=args.debug)
    excludes = []
    if excludes is not None:
        for filter in excludes:
            excludes.append(re.compile(filter))
    namespaces_items = asyncio.run(
        get_node_list_for_path(args.url, args.root, excludes, args.max)
    )
    logging.info(f"Found {len(namespaces_items['items'])} variables")
    # property name depends on type of operation
    property_name = PROP_TRIGGER_ITEMS
    if args.type == "read":
        property_name = PROP_CLIENT_ITEMS
    source_item_list = [
        get_source_props(
            root_path=args.root,
            item_subpath=node["subpath"],
            item_id=node["node_id"],
            namespaces=namespaces_items["namespaces"],
            namespace_int=namespaces_items["root_ns_index"],
            client_item_root=CLIENT_DEFAULT_ROOT,
            prop_name=property_name,
        )
        for node in namespaces_items["items"]
    ]
    property_value = item_list_to_property(source_item_list, property_name)
    property_uri = configurable_property_uri(args.flow, args.node, property_name)
    # if workdir is not set, send to file or stdout
    if args.workdir is None:
        override_line = override_property_line(property_uri, property_value)
        if args.to == "-":
            print(override_line)
        else:
            with open(args.to, "w") as f:
                f.write(override_line)
    else:
        # workdir is set, save directly in application
        props_files = f"{args.workdir}/run/{args.to}/META-INF/broker.xml"
        # check if file exists
        if not os.path.isfile(props_files):
            raise Exception(f"File {props_files} does not exist")
        logging.info(f"Found file {props_files}")
        uri_prop = f'uri="{property_uri}"'
        # read file
        applied = False
        new_props_files = props_files + ".new"
        saved_props_files = props_files + ".original"
        with open(new_props_files, "w") as new_file:
            with open(props_files, "r") as f:
                for line in f:
                    if uri_prop in line:
                        applied = True
                        logging.info(f"Found property {property_uri}")
                        match = re.search(r'^(.* override=")[^"]*(".*)$', line)
                        if not match:
                            raise Exception(f"Invalid line: {line}")
                        line = match.group(1) + property_value + match.group(2) + "\n"
                    new_file.write(line)
        if not applied:
            raise Exception(f"Property {property_uri} not found in {props_files}")
        os.rename(props_files, saved_props_files)
        logging.info(f"Saved original file {saved_props_files}")
        os.rename(new_props_files, props_files)
        logging.info(f"Saved new file {props_files}")


if __name__ == "__main__":
    main()
