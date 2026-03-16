import os
import argparse
from neo4j import GraphDatabase

def main():
    parser = argparse.ArgumentParser(description="Neo4j Cypher CLI Runner")
    parser.add_argument("query", help="The Cypher query to execute")
    args = parser.parse_args()

    # Environment variables
    NEO4J_URI = os.getenv("NEO4J_URI", "bolt://localhost:7687")
    NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
    NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "password")

    try:
        driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
        with driver.session() as session:
            result = session.run(args.query)
            records = [record.data() for record in result]
            
            print(f"Executed query: {args.query}")
            print(f"Returned {len(records)} records:")
            for idx, record in enumerate(records):
                print(f"[{idx}] {record}")
            
    except Exception as e:
        print(f"Error executing query: {e}")
    finally:
        if 'driver' in locals():
            driver.close()

if __name__ == "__main__":
    main()
