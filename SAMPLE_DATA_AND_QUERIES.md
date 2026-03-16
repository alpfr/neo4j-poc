# Neo4j Graph PoC: Sample Data & Queries

This document contains the foundational schema, sample datasets, and interactive visualization queries designed to demonstrate the power of the Neo4j Graph database directly within the deployed Streamlit app.

## The Schema Structure

For this Proof of Concept, we simulate an organization's network structure. 

**Nodes (Entities):**
- **Label**: `Person`
- **Properties**: 
  - `name`: (string) The person's given name
  - `age`: (integer)
  - `role`: (string) The employee's title

**Edges (Relationships):**
- `REPORTS_TO` (Directional hierarchical structure)
- `WORKS_WITH` (Peer collaboration)
- `KNOWS` (Social or professional acquaintance)

---

## 1. Create the Sample Graph (Data Insertion)

Copy and paste the following `Cypher` query into the Streamlit Web Application and click **"Execute Query"**. 

This query simultaneously creates 10 specific individuals and connects them with 8 distinct relationships in a single atomic transaction.

```cypher
CREATE 
  (p1:Person {name: 'Alice', age: 28, role: 'Engineer'}),
  (p2:Person {name: 'Bob', age: 34, role: 'Data Scientist'}),
  (p3:Person {name: 'Charlie', age: 41, role: 'Manager'}),
  (p4:Person {name: 'Diana', age: 29, role: 'Designer'}),
  (p5:Person {name: 'Eve', age: 33, role: 'Product Manager'}),
  (p6:Person {name: 'Frank', age: 45, role: 'Director'}),
  (p7:Person {name: 'Grace', age: 26, role: 'Engineer'}),
  (p8:Person {name: 'Hank', age: 38, role: 'DevOps'}),
  (p9:Person {name: 'Ivy', age: 31, role: 'QA Tester'}),
  (p10:Person {name: 'Jack', age: 27, role: 'Engineer'}),
  
  (p1)-[:KNOWS]->(p2),
  (p2)-[:REPORTS_TO]->(p3),
  (p4)-[:WORKS_WITH]->(p1),
  (p5)-[:REPORTS_TO]->(p6),
  (p7)-[:KNOWS]->(p10),
  (p8)-[:WORKS_WITH]->(p7),
  (p9)-[:REPORTS_TO]->(p5),
  (p10)-[:WORKS_WITH]->(p1)

RETURN *
```
*(Note: Streamlit might display "No tabular data returned" in the table tab after creation because CREATE statements don't cleanly return flat vectors; check the database directly by running a read query below.)*

---

## 2. Query the Graph (Tabular View)

To view the raw property dictionary payloads inside a standard Pandas dataframe just like a traditional SQL database:

```cypher
MATCH (n:Person) RETURN n.name as Name, n.role as Role, n.age as Age LIMIT 10
```
This is a simple node-level scan. Click the **Raw Data (Table)** tab in Streamlit to view the structured results.

---

## 3. Visualize the Graph! (Topology View)

If you only query `MATCH (n)`, Neo4j only returns the disconnected Nodes.
**To interactively visualize the physics graph, you must explicitly instruct Neo4j to return the Relationships (Edges)!**

Copy and paste the following query into the Streamlit app:

```cypher
MATCH (n)-[r]->(m) RETURN n, r, m
```
Click **Execute Query**, and then click the **"Graph Visualization"** Tab.

### Interacting with the Graph
- **Zoom & Pan**: Use your mouse wheel to zoom in to specific nodes, and click-and-drag the canvas to pan across large network topologies.
- **Physics Engine**: Click and drag a Node aggressively; you will see it natively push and pull connected elements until the network stabilizes under its physics constraints!
- **Data Tracing**: By hovering your mouse directly over any node bubble, a tooltip will render its hidden metadata (such as `{name: Alice, role: Engineer}`). 

### Analyzing Path Traversal
You can instantly see how Neo4j removes the need for complex `JOIN` tables:
- Notice how `Diana` and `Jack` connect through `Alice`. 
- Observe the reporting hierarchies flowing upward to `Frank` (Director).
