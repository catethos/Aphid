#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct aphid_db aphid_db;
typedef struct aphid_cursor aphid_cursor;
typedef struct aphid_type aphid_type;
typedef struct aphid_value aphid_value;
typedef struct aphid_params aphid_params;
typedef struct { const uint8_t* data; size_t length; } aphid_bytes;
typedef struct { int32_t code; size_t length; char message[1024]; } aphid_error;
typedef int32_t (*aphid_completion)(void* context, int32_t status);
typedef int32_t (*aphid_cancelled)(void* context);

/* Private ABI 1. Every entry contains exceptions. No function takes ownership
 * of input bytes. Errors are bounded UTF-8/byte diagnostics (length <=1023),
 * possibly truncated; reporting allocates no memory. */
uint32_t aphid_bridge_version(void);
/* Dirty CPU / native thread; may block. Empty path means memory. Returns one
 * owned reference; open failure may retain a quarantined path until cleanup.
 * Session count 1..64, database count <=64 per VM, execution threads 1..64.
 * Code 6 means the canonical path's previous owner is retiring; admission may
 * wait and retry open. Code 2 means an active owner or capacity limit. Neither
 * failure creates an engine or removes the existing owner's reservation. */
aphid_db* aphid_open(const uint8_t* path, size_t length, uint32_t sessions,
                    uint32_t threads, aphid_error* error);
aphid_db* aphid_open_configured(const uint8_t* path, size_t length, uint32_t sessions,
                    uint32_t threads, uint64_t buffer_pool_bytes, aphid_error* error);
/* Nonblocking control, short mutexes only. Retire rejects work immediately.
 * Release consumes one owned reference and requests retirement. All worker
 * joins and engine destruction run in the runtime cleanup thread. */
void aphid_retire(aphid_db* db);
void aphid_release(aphid_db* db);
int32_t aphid_closed(aphid_db* db);
uint64_t aphid_next_id(aphid_db* db);
/* Dirty CPU: copies <=1MiB query. Requires live db reference until callback.
 * Accepted submissions call completion exactly once on the session worker,
 * without engine/control locks. Callback must not throw; 0 abandons result.
 * cancelled is a nonblocking callback, valid until completion returns; monitor
 * must be armed before submission. Nonzero return means no callback occurs. */
int32_t aphid_submit(aphid_db* db, uint32_t session, uint64_t id,
                    const uint8_t* query, size_t length, void* context,
                    aphid_completion complete, aphid_cancelled cancelled,
                    aphid_error* error);
/* Nonblocking reservation before parameter conversion. Sets operation identity
 * and bounds concurrent conversion by session count. Cancel(abandon=1) releases
 * the reservation asynchronously. Returns 0 on success, bounded error otherwise. */
int32_t aphid_reserve(aphid_db* db, uint32_t session, uint64_t id, aphid_error* error);
/* Nonblocking scoped transaction lease. Acquire requires idle and a fresh nonzero
 * identity from next_id. Parent must stay retained until release completes.
 * Release requests cancellation/result cleanup and worker-side rollback; it does
 * not wait. A stale release is harmless. State 4 means idle but still leased;
 * state 0 proves release/rollback completed. Failure retires the session (3).
 * The binding must monitor the lease owner and release on death/timeout/GC. */
int32_t aphid_lease_acquire(aphid_db* db, uint32_t session, uint64_t lease, aphid_error* error);
int32_t aphid_lease_release(aphid_db* db, uint32_t session, uint64_t lease);
/* Reservation authenticated by lease generation; zero means ordinary query.
 * Failed/abandoned leases reject all subsequent work until released. */
int32_t aphid_reserve_lease(aphid_db* db, uint32_t session, uint64_t id,
                          uint64_t lease, aphid_error* error);
/* Nonblocking control submission, reserves its operation itself. Control 1 is
 * begin-write, 2 commit, 3 rollback. Requires nonzero matching lease. Uses the
 * same completion/finish ownership as queries, but has no fetchable result.
 * Commit failure/cancellation is not proof of rollback; the binding must report
 * an uncertain commit outcome. No control operation is retried. */
int32_t aphid_transaction_control(aphid_db* db, uint32_t session, uint64_t id,
    uint64_t lease, uint32_t control, void* context, aphid_completion complete,
    aphid_cancelled cancelled, aphid_error* error);
/* Requires the matching reservation; consumes params on success AND failure.
 * Failure abandons the reservation. A cancelled/stale conversion cannot dispatch
 * into a later operation, even if the session has already been reused. */
int32_t aphid_submit_params(aphid_db* db, uint32_t session, uint64_t id,
                    const uint8_t* query, size_t length, aphid_params* params, void* context,
                    aphid_completion complete, aphid_cancelled cancelled, aphid_error* error);
/* Nonblocking, operation-scoped control. Stale ids have no effect. Cancellation
 * is repeated by a fixed controller until execution ends, covering engine reset
 * races. abandon also releases the eventual result. */
int32_t aphid_cancel(aphid_db* db, uint32_t session, uint64_t id, int32_t abandon);
/* Request result destruction on the owning worker. The session becomes idle
 * only after destruction and completion callback return. */
int32_t aphid_finish(aphid_db* db, uint32_t session, uint64_t id);
/* Nonblocking snapshots: 0 idle, 1 executing, 2 result-ready, 3 retiring/closed,
 * 4 idle with an exclusive transaction lease.
 * Result/error metadata is copied under a short lock; no borrowed data escapes. */
int32_t aphid_session_state(aphid_db* db, uint32_t session);
/* Nonblocking diagnostic snapshot for a matching operation on a ready database.
 * Returns 1 while its exclusive fetch is held, 0 otherwise/unavailable. */
int32_t aphid_transferring(aphid_db* db, uint32_t session, uint64_t id);
int32_t aphid_operation_error(aphid_db* db, uint32_t session, uint64_t id, aphid_error* error);
/* Dirty CPU only. Begin obtains the sole fetch lease for a ready operation.
 * It retains the database independently until end. Close/finish may run while
 * leased but cannot destroy the result/connection or reuse the session.
 * The caller MUST end on every path, on the same thread, including exceptions.
 * Metadata is owned by the cursor; value views expire at next/end. No cursor
 * or borrowed pointer is a BEAM-visible handle. All getters require a live
 * cursor lease and are used only by that lease's thread. */
aphid_cursor* aphid_fetch_begin(aphid_db* db, uint32_t session, uint64_t id, aphid_error* error);
void aphid_fetch_end(aphid_cursor* cursor);
uint64_t aphid_fetch_columns(const aphid_cursor* cursor);
uint64_t aphid_fetch_rows(const aphid_cursor* cursor);
/* Dirty fetch-lease thread only. Position counts consumed rows. Unread retains
 * just the current row for the next fetch, including across fetch_end/begin;
 * returns 1 once, 0 if no current row. Does not copy row values. Finish/close
 * destroys an unread row before its result/statement parents. */
uint64_t aphid_fetch_position(const aphid_cursor* cursor);
int32_t aphid_fetch_unread(aphid_cursor* cursor);
/* 1 success, 0 out of range; output views live until end. */
int32_t aphid_fetch_column(const aphid_cursor* cursor, uint64_t index,
                           aphid_bytes* name, const aphid_type** type);
/* 1 row, 0 EOF, -1 exception; invalidates the previous row's value views. */
int32_t aphid_fetch_next(aphid_cursor* cursor, aphid_error* error);
const aphid_value* aphid_fetch_value(const aphid_cursor* cursor, uint64_t index);
/* Bounded inspectors: no recursive copies or value allocation. The tag is the
 * pinned engine LogicalTypeID. aux fields are precision/scale or array length;
 * children counts descriptor children. Field names use one cursor scratch
 * string and expire at the next type_child call. Copy names before recursion.
 * Input construction may pass a null cursor to borrow child types without names.
 * Value bytes borrow the engine row until next/end. Integer bits are low/high
 * two's complement, sign-extended to 128 bits for signed values. Interval uses
 * low for signed microseconds and months/days; IDs use high=table, low=offset.
 * Inspect returns 0 success, nonzero bounded error (5 unsupported type). */
typedef struct { uint32_t tag; uint64_t aux1, aux2, children; } aphid_type_info;
typedef struct {
    const aphid_type* type;
    int32_t is_null;
    uint64_t low, high, children;
    int32_t months, days;
    double real;
    aphid_bytes bytes;
} aphid_value_info;
int32_t aphid_type_inspect(const aphid_type* type, aphid_type_info* out, aphid_error* error);
int32_t aphid_type_child(aphid_cursor* cursor, const aphid_type* type, uint64_t index,
                         const aphid_type** child, aphid_bytes* name, aphid_error* error);
int32_t aphid_value_inspect(const aphid_value* value, aphid_value_info* out, aphid_error* error);
const aphid_value* aphid_value_child(const aphid_value* value, uint64_t index);
/* Dirty CPU input construction, before dispatch. Types copy borrowed children
 * and names. Values copy scalar bytes and consume ALL owned child values on
 * success/failure (their array slots become null). MAP children are flattened
 * key,value pairs; other containers use one value per child. Null has none.
 * Owned inputs must be freed on all paths; never free borrowed result views.
 * Params.add consumes its value on success/failure, copies its name, rejects
 * duplicate names. Params are transferred to the worker by submit_params.
 * Each call contains exceptions; null/nonzero is failure with bounded error.
 * The Zig caller enforces total bytes/depth and checks cancellation between
 * calls; no process-bound environment is used by these functions. */
aphid_type* aphid_type_make(uint32_t tag, uint64_t aux1, uint64_t aux2,
    const aphid_type* const* children, const aphid_bytes* names, size_t count, aphid_error* error);
void aphid_type_free(aphid_type* type);
aphid_value* aphid_value_make(const aphid_type* type, const aphid_value_info* scalar,
    aphid_value** children, size_t count, aphid_error* error);
void aphid_value_free(aphid_value* value);
aphid_params* aphid_params_new(aphid_error* error);
int32_t aphid_params_add(aphid_params* params, aphid_bytes name, aphid_value* value, aphid_error* error);
void aphid_params_free(aphid_params* params);
uint32_t aphid_live_databases(void);
uint32_t aphid_live_workers(void);
#ifdef __cplusplus
}
#endif
