#!/usr/bin/env python3
"""
https://github.com/FreeOpcUa/python-opcua

https://github.com/FreeOpcUa/opcua-asyncio

https://github.com/FreeOpcUa/opcua-client-gui

uabrowse -u ${opcua_server_url} -l 0 -d 10 -p 'Objects,2:OpcPlc,2:Telemetry'

./generate_var_list_property.py 'OPCUA_process' 'OPC-UA-Input' $opcua_server_url 0:Objects/2:OpcPlc/2:Telemetry/2:Basic http://microsoft.com/Opc/OpcPlc/

ibmint apply overrides $ace_container_work_directory/abc.txt --work-directory $ace_container_work_directory
"""

import os
import re
import sys
import asyncio
import argparse
import logging
import urllib.parse
import uuid
from asyncua import Client, ua

# properties in message flow XML
PROP_TRIGGER = 'triggerItemList'
PROP_SERVER = 'opcUaServerList'
# default source uuid
SOURCE_ROOT_UUID = "00000000-0000-1000-8000-000000000002"
# Default source path
SOURCE_DEFAULT_ROOT = "/Source"
CLIENT_DEFAULT_ROOT = "/Item"


async def find_all(parent, result: list = None, parent_path: list = []):
    """
    The result returns the sub path part only without namespace, e.g. ['f1/m1','f1/m2]
    """
    if result is None:
        result = []
    for node in await parent.get_children():
        attrs = await node.read_attributes(
            [
                ua.AttributeIds.BrowseName,
                ua.AttributeIds.NodeClass,
                ua.AttributeIds.NodeId
            ]
        )
        browse_name, child_class, node_id = [
            attr.Value.Value for attr in attrs]
        simple_name = browse_name.to_string().split(":")[-1]
        child_path = parent_path + [simple_name]
        logging.debug(f"{simple_name} : {node_id}")
        if child_class == ua.NodeClass.Variable:
            result.append(
                {"subpath": "/".join(child_path), "node_id": node_id.to_string()})
        else:
            await find_all(node, result, child_path)
    return result


async def get_node_list_for_path(url, selection_filter):
    logging.info(f"Connecting to {url} ...")
    async with Client(url=url) as client:
        logging.info(f"Connected.")
        path_selection = selection_filter.split("/")
        selected_root = await client.nodes.root.get_child(path_selection)
        logging.info(f"Root node found: {selected_root.nodeid.to_string()}")
        return await find_all(selected_root)


def item_to_uri_params(info: dict):
    """
    Encode info dict to URI
    Args:
        info: one source or server information
        suffix: suffix to add to URI, empty for server, '|||' for source
    """
    suffix = ""
    if 'SOURCE_ITEM_ADDR' in info:
        suffix = '|||'
    encoded_pairs = []
    for key, value in info.items():
        if isinstance(value, str):
            value = urllib.parse.quote(str(value), safe=':/;#[] *')
        else:
            value = str(value).lower()
        encoded_pairs.append(f"{key}={value}")
    return f"{info['MAPPING_ID']}:{info['MAPPING_PATH']}?{'$'.join(encoded_pairs)}{suffix}"


def trigger_list_to_property(item_list):
    """Convert list of items in dict to property triggerItemList"""
    src_list = ["4"]
    for item in item_list:
        src_list.append(item_to_uri_params(item))
    return ','.join(src_list)


def get_tag_value(tagname, text):
    """get first match for property in xml"""
    match = re.search(rf'{tagname}="([^"]+)"', text)
    if not match:
        raise Exception("No match in flow")
    return match.group(1)


def replace_tag(tagname, text, value):
    """replace first match"""
    return re.sub(rf'{tagname}="([^"]+)"', f'{tagname}="{value}"', text)


def get_source_props(root_path: str, item_subpath: str, item_id: str, namespace_str: str, namespace_int: int = 2, client_item_root: str = 'Item'):
    """
    Get source properties for one item
    Args:
        root_path: root path of source, e.g. '0:Objects/2:OpcPlc/2:Telemetry'
        item_subpath: subpath of item, e.g. 'Fast/FastDouble1'
        namespace_str: namespace string, e.g. 'http://microsoft.com/Opc/OpcPlc/'
        namespace_int: namespace index, e.g. 2
    """
    item_subpath_array = item_subpath.split('/')
    # last group in path
    last_one = root_path.split('/')[-1].split(':')[1]
    # /Objects/2:OpcPlc/2:Telemetry/2:Fast/2:FastDouble1
    source_item_path = '/'.join([root_path] + [
                                f"{namespace_int}:{item}" for item in item_subpath_array])
    logging.info(f"Source item path: {source_item_path}")
    # /Item/Telemetry/Fast/FastDouble1
    mapping_path = '/'.join(["", client_item_root,
                            last_one]+item_subpath_array)
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
        "SOURCE_ITEM_NS": namespace_str,
        "SOURCE_ITEM_PATH": source_item_path,
        "SOURCE_PATH": SOURCE_DEFAULT_ROOT,
        "SOURCE_REF": SOURCE_ROOT_UUID,
        "VERSION_TIME": "2023-06-09T07:29:29.380+0000"
    }


def override_property_line(flow_name: str, node_name: str, prop_name: str, prop_value: str):
    """Write property to file"""
    return f"{flow_name}#{node_name}.{prop_name}={prop_value}\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--loglvl", help="log level", type=int, default=30)
    parser.add_argument("flow", help="flow name")
    parser.add_argument("node", help="node name")
    parser.add_argument("url", help="OPC UA server URL")
    parser.add_argument("path", help="root of dump")
    parser.add_argument(
        "namespace", help="namespace, e.g. http://microsoft.com/Opc/OpcPlc/")
    args = parser.parse_args()
    logging.basicConfig(level=args.loglvl)
    nodes_descr = asyncio.run(get_node_list_for_path(args.url, args.path))
    logging.info(f"Found {len(nodes_descr)} variables")
    source_item_list1 = [get_source_props(
        args.path, node['subpath'], node['node_id'], args.namespace) for node in nodes_descr]
    print(override_property_line(args.flow, args.node, PROP_TRIGGER,
                                 trigger_list_to_property(source_item_list1)))

