import Foundation

/// Protocol abstracting database operations for testability.
/// DAOs can accept any conforming type, enabling in-memory test databases.
protocol DatabaseManaging: AnyObject {
    func execute(sql: String, parameters: [Any])
    func query(sql: String, parameters: [Any]) -> [[String: Any]]
    @discardableResult
    func executeInsert(sql: String, parameters: [Any]) -> Int64
    func executeBatch(sql: String)
    func inTransaction(_ block: (DatabaseManager.TransactionContext) throws -> Void) rethrows
    func tryExecute(sql: String, parameters: [Any]) throws
    func tryQuery(sql: String, parameters: [Any]) throws -> [[String: Any]]
}

// Default parameter values via extension
extension DatabaseManaging {
    func execute(sql: String) { execute(sql: sql, parameters: []) }
    func query(sql: String) -> [[String: Any]] { query(sql: sql, parameters: []) }
    @discardableResult
    func executeInsert(sql: String) -> Int64 { executeInsert(sql: sql, parameters: []) }
    func tryExecute(sql: String) throws { try tryExecute(sql: sql, parameters: []) }
    func tryQuery(sql: String) throws -> [[String: Any]] { try tryQuery(sql: sql, parameters: []) }
}

// Conform DatabaseManager to the protocol
extension DatabaseManager: DatabaseManaging {}
