#!/usr/bin/env python3
"""
https://github.com/FreeOpcUa/python-opcua

https://github.com/FreeOpcUa/opcua-asyncio

https://github.com/FreeOpcUa/opcua-client-gui

uabrowse -u ${opcua_server_url} -l 0 -d 10 -p 'Objects,2:OpcPlc,2:Telemetry'
"""

import os
import asyncio
from asyncua import Client, ua

url = os.environ['opcua_server_url']
# index 2
namespace = "http://microsoft.com/Opc/OpcPlc/"


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


async def main():
    print(f"Connecting to {url} ...")
    async with Client(url=url) as client:
        # Find the namespace index
        nsidx = await client.get_namespace_index(namespace)
        print(f"Namespace Index for '{namespace}': {nsidx}")
        # Get the variable node for read / write
        myroot = ["0:Objects", f"{nsidx}:OpcPlc", f"{nsidx}:Telemetry"]
        mynode = await client.nodes.root.get_child(myroot)
        await browse(mynode, myroot)

if __name__ == "__main__":
    asyncio.run(main())
