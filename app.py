import streamlit as st
import os
from neo4j import GraphDatabase
import pandas as pd

# Environment variables
NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

st.set_page_config(page_title="Neo4j Streamlit PoC", layout="wide")
st.title("Neo4j Cypher Runner (Streamlit)")

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
                result = session.run(query)
                records = [record.data() for record in result]
                if records:
                    st.success(f"Returned {len(records)} records")
                    st.dataframe(pd.DataFrame(records))
                else:
                    st.warning("Query executed successfully but returned no data.")
        except Exception as e:
            st.error(f"Error executing query: {e}")
    else:
        st.error("Please enter a query.")
