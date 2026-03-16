import streamlit as st
import os
from neo4j import GraphDatabase
import pandas as pd
from streamlit_agraph import agraph, Node, Edge, Config

# Environment variables
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

st.set_page_config(page_title="Neo4j Streamlit PoC", layout="wide")
st.title("Neo4j Cypher Runner & Visualizer")

@st.cache_resource
def get_driver():
    return GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))

try:
    driver = get_driver()
except Exception as e:
    st.error(f"Failed to connect to Neo4j. Please check your credentials and URI. Error: {e}")
    st.stop()

query = st.text_area("Enter Cypher Query", "MATCH (n) RETURN n LIMIT 10")

if st.button("Execute Query"):
    if query:
        try:
            with driver.session() as session:
                # 1. Fetch graph specifically to map the topological visualization
                result = session.run(query)
                graph = result.graph()
                
                nodes = []
                edges = []
                
                for n in graph.nodes:
                    label = list(n.labels)[0] if n.labels else "Node"
                    # Try to extract a meaningful title for the bubble from neo4j standard property patterns
                    title_attr = n.get("name", n.get("title", n.get("id", label)))
                    nodes.append(Node(id=n.element_id, label=str(title_attr), title=f"{label}: {dict(n.items())}", color="#4a90e2"))
                    
                for r in graph.relationships:
                    edges.append(Edge(source=r.start_node.element_id, target=r.end_node.element_id, label=r.type, type="CURVE_SMOOTH"))
                
                st.success("Query Executed Successfully.")
                
                # We create tabs to show the awesome Graph UI vs the generic Pandas table
                tab1, tab2 = st.tabs(["Graph Visualization", "Raw Data (Table)"])
                
                with tab1:
                    if nodes:
                        config = Config(width=800, height=600, directed=True, physics=True, hierarchical=False)
                        agraph(nodes=nodes, edges=edges, config=config)
                    else:
                        st.info("No nodes or relationships were returned in the Graph topology.")
                        if "LIMIT" in query.upper():
                            st.write("*Tip: To draw a graph, make sure you RETURN relationships too, e.g., `MATCH (n)-[r]->(m) RETURN n, r, m LIMIT 10`*")
                        
                with tab2:
                    # In neo4j python driver 5.x, calling .graph() consumes the cursor. We rerun quickly to fetch raw records for the table layout.
                    result_data = session.run(query)
                    records = []
                    for row in result_data:
                        safe_row = {}
                        for key, value in row.data().items():
                            # Force everything to be a string unless it's a basic primitive, avoiding ALL Pandas type errors
                            if isinstance(value, (int, float, str, bool)) and value is not None:
                                safe_row[key] = value
                            else:
                                safe_row[key] = str(value)
                        records.append(safe_row)
                        
                    if records:
                        st.dataframe(pd.DataFrame(records))
                    else:
                        st.info("No tabular data returned.")
                        
        except Exception as e:
            st.error(f"Error executing query: {e}")
    else:
        st.error("Please enter a query.")
