#!/usr/bin/env python3
"""
https://github.com/FreeOpcUa/python-opcua

https://github.com/FreeOpcUa/opcua-asyncio

https://github.com/FreeOpcUa/opcua-client-gui

uabrowse -u ${opcua_server_url} -l 0 -d 10 -p 'Objects,2:OpcPlc,2:Telemetry'
"""

import os
import sys
import asyncio
from asyncua import Client, ua


async def browse(parent, path):
    for node in await parent.get_children():
        attrs = await node.read_attributes(
            [
                ua.AttributeIds.BrowseName,
                ua.AttributeIds.NodeClass
            ]
        )
        name, child_class = [attr.Value.Value for attr in attrs]
        child_path = path + [name.to_string()]
        if child_class == ua.NodeClass.Variable:
            print("/".join(child_path))
        else:
            await browse(node, child_path)


async def main(url, selection_filter):
    print(f"Connecting to {url} ...")
    async with Client(url=url) as client:
        path_selection = selection_filter.split("/")
        selected_root = await client.nodes.root.get_child(path_selection)
        await browse(selected_root, path_selection)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage :   list_variables.py <opcua_server_url> <selection_filter>")
        print("Example : list_variables.py $opcua_server_url 0:Objects/2:OpcPlc/2:Telemetry")
        sys.exit(1)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
