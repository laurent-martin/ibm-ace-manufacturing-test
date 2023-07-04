#!/usr/bin/env python3
"""
https://github.com/FreeOpcUa/python-opcua

https://github.com/FreeOpcUa/opcua-asyncio

https://github.com/FreeOpcUa/opcua-client-gui

sudo dnf install -y python39

pip3 install --user asyncua

uabrowse -u $opcua_server_url -l 0 -d 10 -p 'Objects,2:OpcPlc,2:Telemetry'

./generate_var_list_property.py --flow OPCUA_process --node OPC-UA-Input --url $opcua_server_url --root 0:Objects/2:OpcPlc/2:Telemetry --out $ace_host_work_directory/ua_overrides.txt
--excludes '["Special/","ABCDEFGH"]'
ibmint apply overrides $ace_container_work_directory/ua_overrides.txt --work-directory $ace_container_work_directory
"""

import re
import json
import uuid
import asyncio
import argparse
import logging
import urllib.parse
from asyncua import Client, ua

# properties in message flow XML
PROP_TRIGGER = "triggerItemList"
PROP_SERVER = "opcUaServerList"
# default source uuid
SOURCE_ROOT_UUID = "00000000-0000-1000-8000-000000000002"
# Default source path
SOURCE_DEFAULT_ROOT = "/Source"
# Default client item path
CLIENT_DEFAULT_ROOT = "/Item"


async def find_all(
    parent, excludes=None, result: list = None, parent_path: list = [], max_items=None
):
    """
    :return: list of items under specified parent node with format: {"subpath": "the/sub/path", "node_id": "ns=2; the node id"}
    """
    if result is None:
        result = []
    for node in await parent.get_children():
        if result and max_items and len(result) >= max_items:
            return result
        attrs = await node.read_attributes(
            [
                ua.AttributeIds.BrowseName,
                ua.AttributeIds.NodeId,
                ua.AttributeIds.NodeClass,
            ]
        )
        browse_name, node_id, child_class = [attr.Value.Value for attr in attrs]
        simple_name = browse_name.to_string().split(":")[-1]
        child_path = parent_path + [simple_name]
        sub_path = "/".join(child_path)
        identifier = node_id.to_string()
        to_exclude = False
        for test_re in excludes:
            if re.match(test_re, sub_path):
                to_exclude = True
                break
        if to_exclude:
            logging.debug(f"excluding {sub_path} : {identifier}")
            continue
        if child_class == ua.NodeClass.Variable:
            logging.debug(f"adding {sub_path} : {identifier}")
            result.append({"subpath": sub_path, "node_id": identifier})
        else:
            logging.debug(f"browsing {sub_path} : {identifier}")
            await find_all(node, excludes, result, child_path, max_items)
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


def trigger_list_to_property(item_list):
    """
    Convert list of items in dict to property value string suitable for triggerItemList
    """
    src_list = ["4"]
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
    # last group in path
    last_one = root_path.split("/")[-1].split(":")[1]
    # /Objects/2:OpcPlc/2:Telemetry/2:Fast/2:FastDouble1
    source_item_path = "/".join(
        [root_path] + [f"{namespace_int}:{item}" for item in item_subpath_array]
    )
    logging.debug(f"Source item path: {source_item_path}")
    # /Item/Telemetry/Fast/FastDouble1
    mapping_path = "/".join([client_item_root, last_one] + item_subpath_array)
    logging.debug(f"Item: {mapping_path} : {item_id}")
    return {
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


def override_property_line(
    flow_name: str, node_name: str, prop_name: str, prop_value: str
):
    """
    one line of override property file suitable for ibmint apply overrides
    """
    return f"{flow_name}#{node_name}.{prop_name}={prop_value}\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--debug",
        help="log level, debug=10, info=20, warning=30 (default)",
        type=int,
        default=30,
    )
    parser.add_argument("--flow", help="flow name", type=str, required=True)
    parser.add_argument("--node", help="node name", type=str, required=True)
    parser.add_argument("--out", help="output file name", type=str, required=True)
    parser.add_argument("--max", help="max number of items", type=int)
    parser.add_argument("--url", help="OPC UA server URL", type=str, required=True)
    parser.add_argument("--root", help="root path", type=str, default=None)
    parser.add_argument(
        "--excludes",
        help="filter JSON with regex to exclude",
        type=json.loads,
        default=None,
    )
    args = parser.parse_args()
    logging.basicConfig(level=args.debug)
    excludes = []
    if args.excludes is not None:
        for filter in args.excludes:
            excludes.append(re.compile(filter))
    namespaces_items = asyncio.run(
        get_node_list_for_path(args.url, args.root, excludes, args.max)
    )
    logging.info(f"Found {len(namespaces_items['items'])} variables")
    source_item_list1 = [
        get_source_props(
            root_path=args.root,
            item_subpath=node["subpath"],
            item_id=node["node_id"],
            namespaces=namespaces_items["namespaces"],
            namespace_int=namespaces_items["root_ns_index"],
            client_item_root=CLIENT_DEFAULT_ROOT,
        )
        for node in namespaces_items["items"]
    ]
    with open(args.out, "w") as f:
        f.write(
            override_property_line(
                args.flow,
                args.node,
                PROP_TRIGGER,
                trigger_list_to_property(source_item_list1),
            )
        )
