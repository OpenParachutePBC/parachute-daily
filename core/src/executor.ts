import type Database from "better-sqlite3";
import type { ToolDef, Thing, Edge, QueryOpts } from "./types.js";
import * as things from "./things.js";
import * as edges from "./edges.js";
import { getTool } from "./tools.js";

/**
 * Execute a tool by name with given parameters.
 * Tools are declarative graph operations — no LLM involved.
 */
export function executeTool(
  db: Database.Database,
  toolName: string,
  params: Record<string, unknown>,
): unknown {
  const tool = getTool(db, toolName);
  if (!tool) throw new Error(`Tool not found: ${toolName}`);
  if (!tool.enabled) throw new Error(`Tool is disabled: ${toolName}`);

  validateParams(tool, params);

  const def = resolveParams(tool.definition, params);
  return executeDefinition(db, tool, def);
}

function executeDefinition(
  db: Database.Database,
  tool: ToolDef,
  def: Record<string, unknown>,
): unknown {
  const action = def.action as string;

  switch (action) {
    case "query_things":
      return executeQueryThings(db, def);
    case "search_things":
      return executeSearchThings(db, def);
    case "traverse":
      return executeTraverse(db, def);
    case "query_edges":
      return executeQueryEdges(db, def);
    case "upsert_thing":
      return executeUpsertThing(db, def);
    case "update_thing":
      return executeUpdateThing(db, def);
    case "create_edge":
      return executeCreateEdge(db, def);
    case "delete_edge":
      return executeDeleteEdge(db, def);
    case "delete_thing":
      return executeDeleteThing(db, def);
    case "tag_thing":
      return executeTagThing(db, def);
    case "untag_thing":
      return executeUntagThing(db, def);
    default:
      throw new Error(`Unknown tool action: ${action}`);
  }
}

// ---- Query Actions ----

function executeQueryThings(db: Database.Database, def: Record<string, unknown>): Thing[] {
  return things.queryThings(db, {
    tags: def.tags as string[] | undefined,
    filters: def.filters as QueryOpts["filters"],
    sort: def.sort as string | undefined,
    limit: def.limit as number | undefined,
    offset: def.offset as number | undefined,
  });
}

function executeSearchThings(db: Database.Database, def: Record<string, unknown>): Thing[] {
  const query = def.query as string;
  if (!query) throw new Error("search_things requires a query parameter");
  return things.searchThings(db, query, {
    tags: def.tags as string[] | undefined,
    limit: def.limit as number | undefined,
  });
}

function executeTraverse(db: Database.Database, def: Record<string, unknown>): Thing[] {
  const from = def.from as string;
  if (!from) throw new Error("traverse requires a 'from' parameter");
  return edges.traverse(db, from, {
    edge: def.edge as string | undefined,
    direction: def.direction as "outbound" | "inbound" | "both" | undefined,
    depth: def.depth as number | undefined,
    targetTags: def.target_tags as string[] | undefined,
    limit: def.limit as number | undefined,
  });
}

function executeQueryEdges(db: Database.Database, def: Record<string, unknown>): Edge[] {
  const from = def.from as string;
  if (!from) throw new Error("query_edges requires a 'from' parameter");
  return edges.getEdges(db, from, {
    relationship: def.edge as string | undefined,
    direction: def.direction as "outbound" | "inbound" | "both" | undefined,
  });
}

// ---- Mutation Actions ----

function executeUpsertThing(db: Database.Database, def: Record<string, unknown>): Thing {
  const content = (def.content as string) ?? "";
  const id = def.id as string | undefined;
  const idTemplate = def.id_template as string | undefined;
  const createdBy = def.created_by as string | undefined;

  // Resolve ID from template if provided
  const resolvedId = idTemplate ?? id;

  // Parse tags: { "card": { "card_type": "reflection" } } → TagInput[]
  const tagInputs =
    def.tags && typeof def.tags === "object"
      ? Object.entries(def.tags as Record<string, Record<string, unknown>>).map(
          ([name, fields]) => ({ name, fields }),
        )
      : undefined;

  // Check if thing already exists (for upsert)
  if (resolvedId) {
    const existing = things.getThing(db, resolvedId);
    if (existing) {
      return things.updateThing(db, resolvedId, { content, tags: tagInputs });
    }
  }

  return things.createThing(db, content, {
    id: resolvedId,
    tags: tagInputs,
    createdBy,
  });
}

function executeUpdateThing(db: Database.Database, def: Record<string, unknown>): Thing {
  const id = def.id as string;
  if (!id) throw new Error("update_thing requires an 'id' parameter");
  return things.updateThing(db, id, {
    content: def.content as string | undefined,
    status: def.status as string | undefined,
  });
}

function executeCreateEdge(db: Database.Database, def: Record<string, unknown>): Edge {
  const source = def.source as string;
  const target = def.target as string;
  const relationship = def.relationship as string;
  if (!source || !target || !relationship) {
    throw new Error("create_edge requires source, target, and relationship");
  }
  return edges.createEdge(db, source, target, relationship, {
    properties: def.properties as Record<string, unknown> | undefined,
    createdBy: def.created_by as string | undefined,
  });
}

function executeDeleteThing(db: Database.Database, def: Record<string, unknown>): { deleted: boolean } {
  const id = def.id as string;
  if (!id) throw new Error("delete_thing requires an 'id' parameter");
  things.deleteThing(db, id);
  return { deleted: true };
}

function executeTagThing(db: Database.Database, def: Record<string, unknown>): { tagged: boolean } {
  const id = def.thing_id as string;
  const tagName = def.tag_name as string;
  if (!id || !tagName) throw new Error("tag_thing requires 'thing_id' and 'tag_name'");
  const fields = (def.fields as Record<string, unknown>) ?? {};
  things.tagThing(db, id, tagName, fields);
  return { tagged: true };
}

function executeUntagThing(db: Database.Database, def: Record<string, unknown>): { untagged: boolean } {
  const id = def.thing_id as string;
  const tagName = def.tag_name as string;
  if (!id || !tagName) throw new Error("untag_thing requires 'thing_id' and 'tag_name'");
  things.untagThing(db, id, tagName);
  return { untagged: true };
}

function executeDeleteEdge(db: Database.Database, def: Record<string, unknown>): { deleted: boolean } {
  const source = def.source as string;
  const target = def.target as string;
  const relationship = def.relationship as string;
  if (!source || !target || !relationship) {
    throw new Error("delete_edge requires source, target, and relationship");
  }
  edges.deleteEdge(db, source, target, relationship);
  return { deleted: true };
}

// ---- Input Validation ----

const JSON_SCHEMA_TYPES: Record<string, (v: unknown) => boolean> = {
  string: (v) => typeof v === "string",
  number: (v) => typeof v === "number",
  boolean: (v) => typeof v === "boolean",
  array: (v) => Array.isArray(v),
  object: (v) => typeof v === "object" && v !== null && !Array.isArray(v),
};

/**
 * Validate tool parameters against the tool's inputSchema.
 * Checks required fields and basic type correctness.
 */
function validateParams(tool: ToolDef, params: Record<string, unknown>): void {
  const schema = tool.inputSchema;
  if (!schema || typeof schema !== "object") return;

  const required = (schema.required as string[]) ?? [];
  const properties = (schema.properties as Record<string, Record<string, unknown>>) ?? {};

  // Check required fields
  for (const field of required) {
    if (params[field] === undefined || params[field] === null) {
      throw new Error(
        `Tool '${tool.name}' requires parameter '${field}'`,
      );
    }
  }

  // Check types for provided fields
  for (const [key, value] of Object.entries(params)) {
    const propDef = properties[key];
    if (!propDef) continue; // Allow extra params (forward-compatible)

    const expectedType = propDef.type as string | undefined;
    if (!expectedType) continue;

    const checker = JSON_SCHEMA_TYPES[expectedType];
    if (checker && !checker(value)) {
      throw new Error(
        `Tool '${tool.name}' parameter '${key}' must be ${expectedType}, got ${typeof value}`,
      );
    }
  }
}

// ---- Parameter Resolution ----

/**
 * Recursively resolve $param references in a definition object.
 * Unresolved $params are removed (set to undefined) so they don't
 * get passed as literal "$foo" strings to SQL queries.
 */
function resolveParams(
  obj: Record<string, unknown>,
  params: Record<string, unknown>,
): Record<string, unknown> {
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(obj)) {
    if (typeof value === "string" && value.startsWith("$")) {
      const paramName = value.slice(1);
      const resolved = params[paramName];
      if (resolved !== undefined) {
        result[key] = resolved;
      }
      // Omit key entirely if param not provided
    } else if (Array.isArray(value)) {
      result[key] = value.map((item) => {
        if (typeof item === "string" && item.startsWith("$")) {
          return params[item.slice(1)];
        }
        if (typeof item === "object" && item !== null) {
          return resolveParams(item as Record<string, unknown>, params);
        }
        return item;
      });
    } else if (typeof value === "object" && value !== null) {
      result[key] = resolveParams(value as Record<string, unknown>, params);
    } else {
      result[key] = value;
    }
  }

  return result;
}
