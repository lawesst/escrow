// Escrow: buyer creates deal; seller can release, buyer can refund.
// Expanded: deadline, memo, events, optional arbitrator.
// Build: move-stylus build && move-stylus test

module escrow::escrow;

use stylus::{
    event::emit,
    tx_context::TxContext,
    object::{Self, UID},
    transfer::{Self},
};

#[test_only]
use stylus::test_scenario;

const PENDING: u8 = 0;
const RELEASED: u8 = 1;
const REFUNDED: u8 = 2;

// -----------------------------------------------------------------------------
// Events
// -----------------------------------------------------------------------------

#[ext(event(indexes = 3))]
public struct EscrowCreated has copy, drop {
    escrow_id: address,
    buyer: address,
    seller: address,
    amount: u64,
}

#[ext(event(indexes = 2))]
public struct EscrowReleased has copy, drop {
    escrow_id: address,
    seller: address,
}

#[ext(event(indexes = 2))]
public struct EscrowRefunded has copy, drop {
    escrow_id: address,
    buyer: address,
}

// -----------------------------------------------------------------------------
// Escrow struct
// -----------------------------------------------------------------------------

/// One escrow deal. Optional deadline (0 = none); optional memo; optional arbitrator.
public struct Escrow has key {
    id: UID,
    buyer: address,
    seller: address,
    amount: u64,
    status: u8,
    /// Unix timestamp; seller cannot release after this. 0 = no deadline.
    deadline: u64,
    /// Optional memo (e.g. deal description).
    memo: vector<u8>,
    /// Optional arbitrator; if not 0x0, can call release or refund to resolve disputes.
    arbitrator: address,
}

/// Create a new escrow. Caller is the buyer; in production they must send amount as msg.value.
/// deadline: 0 = no deadline; else Unix timestamp after which only buyer can refund.
entry fun create(
    seller: address,
    amount: u64,
    deadline: u64,
    memo: vector<u8>,
    arbitrator: address,
    ctx: &mut TxContext,
) {
    assert!(seller != ctx.sender(), 1);  // EBuyerIsSeller
    assert!(amount > 0, 2);               // EZeroAmount
    let id = object::new(ctx);
    let escrow = Escrow {
        id,
        buyer: ctx.sender(),
        seller,
        amount,
        status: PENDING,
        deadline,
        memo,
        arbitrator,
    };
    emit(EscrowCreated {
        escrow_id: object::uid_to_address(&escrow.id),
        buyer: escrow.buyer,
        seller: escrow.seller,
        amount: escrow.amount,
    });
    transfer::share_object(escrow);
}

/// Seller confirms: release funds to seller. Fails if past deadline.
#[ext(shared_objects(escrow))]
entry fun release(escrow: &mut Escrow, ctx: &TxContext) {
    assert!(escrow.status == PENDING, 3);
    assert!(
        ctx.sender() == escrow.seller || ctx.sender() == escrow.arbitrator,
        4
    ); // ENotSellerOrArbitrator
    assert!(
        escrow.deadline == 0 || ctx.block_timestamp() < escrow.deadline,
        6
    ); // EDeadlinePassed
    escrow.status = RELEASED;
    emit(EscrowReleased {
        escrow_id: object::uid_to_address(&escrow.id),
        seller: escrow.seller,
    });
}

/// Buyer cancels: refund to buyer. Arbitrator can also refund.
#[ext(shared_objects(escrow))]
entry fun refund(escrow: &mut Escrow, ctx: &TxContext) {
    assert!(escrow.status == PENDING, 3);
    assert!(
        ctx.sender() == escrow.buyer || ctx.sender() == escrow.arbitrator,
        5
    ); // ENotBuyerOrArbitrator
    escrow.status = REFUNDED;
    emit(EscrowRefunded {
        escrow_id: object::uid_to_address(&escrow.id),
        buyer: escrow.buyer,
    });
}

// -----------------------------------------------------------------------------
// Views
// -----------------------------------------------------------------------------

#[ext(abi(view), shared_objects(escrow))]
entry fun buyer(escrow: &Escrow): address {
    escrow.buyer
}

#[ext(abi(view), shared_objects(escrow))]
entry fun seller(escrow: &Escrow): address {
    escrow.seller
}

#[ext(abi(view), shared_objects(escrow))]
entry fun amount(escrow: &Escrow): u64 {
    escrow.amount
}

#[ext(abi(view), shared_objects(escrow))]
entry fun status(escrow: &Escrow): u8 {
    escrow.status
}

#[ext(abi(view), shared_objects(escrow))]
entry fun deadline(escrow: &Escrow): u64 {
    escrow.deadline
}

#[ext(abi(view), shared_objects(escrow))]
entry fun memo(escrow: &Escrow): vector<u8> {
    escrow.memo
}

#[ext(abi(view), shared_objects(escrow))]
entry fun arbitrator(escrow: &Escrow): address {
    escrow.arbitrator
}

#[ext(abi(view), shared_objects(escrow))]
entry fun is_pending(escrow: &Escrow): bool {
    escrow.status == PENDING
}

/// True if deadline is set and current time >= deadline (pass current_timestamp from client).
#[ext(abi(view), shared_objects(escrow))]
entry fun is_expired(escrow: &Escrow, current_timestamp: u64): bool {
    escrow.deadline != 0 && current_timestamp >= escrow.deadline
}

// -----------------------------------------------------------------------------
// Unit tests
// -----------------------------------------------------------------------------

#[test]
fun test_create_and_views() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x1);
    let uid = object::new(&mut ctx);
    let e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"deal",
        arbitrator: @0x0,
    };

    assert!(e.buyer() == @0x1, 0);
    assert!(e.seller() == @0x2, 0);
    assert!(e.amount() == 100, 0);
    assert!(e.deadline() == 0, 0);
    assert!(e.memo() == b"deal", 0);
    assert!(e.arbitrator() == @0x0, 0);
    assert!(e.is_pending(), 0);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_release_by_seller() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x2);
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 50,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0x0,
    };

    e.release(&ctx);
    assert!(e.status() == RELEASED, 0);
    assert!(!e.is_pending(), 0);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_refund_by_buyer() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x1);
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 75,
        status: PENDING,
        deadline: 999,
        memo: b"",
        arbitrator: @0x0,
    };

    e.refund(&ctx);
    assert!(e.status() == REFUNDED, 0);
    assert!(!e.is_pending(), 0);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_release_by_arbitrator() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0xA); // arbitrator
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0xA,
    };

    e.release(&ctx);
    assert!(e.status() == RELEASED, 0);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_refund_by_arbitrator() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0xB); // arbitrator
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0xB,
    };

    e.refund(&ctx);
    assert!(e.status() == REFUNDED, 0);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_release_by_non_seller_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x99);
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0x0,
    };

    e.release(&ctx);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_refund_by_non_buyer_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x99);
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0x0,
    };

    e.refund(&ctx);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_release_after_refund_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x1);
    let uid = object::new(&mut ctx);
    let mut e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 0,
        memo: b"",
        arbitrator: @0x0,
    };
    e.refund(&ctx);

    test_scenario::set_sender_address(@0x2);
    e.release(&ctx);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_is_expired() {
    let mut ctx = test_scenario::new_tx_context();
    let uid = object::new(&mut ctx);
    let e = Escrow {
        id: uid,
        buyer: @0x1,
        seller: @0x2,
        amount: 100,
        status: PENDING,
        deadline: 1000,
        memo: b"",
        arbitrator: @0x0,
    };

    assert!(!e.is_expired(999), 0);
    assert!(e.is_expired(1000), 0);
    assert!(e.is_expired(1001), 0);
    assert!(!e.is_expired(0), 0); // deadline 0 = never expired

    test_scenario::drop_storage_object(e);
}
