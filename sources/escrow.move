// Simple Escrow: buyer creates deal with seller and amount; seller can release, buyer can refund.
// Build: move-stylus build && move-stylus test
//
// Flow: Buyer calls create(seller, amount) and sends amount as msg.value. Seller calls
// release(escrow) to mark as released; buyer calls refund(escrow) to cancel.

module escrow::escrow;

use stylus::{
    tx_context::TxContext,
    object::{Self, UID},
    transfer::{Self},
};

#[test_only]
use stylus::test_scenario;

const PENDING: u8 = 0;
const RELEASED: u8 = 1;
const REFUNDED: u8 = 2;

/// One escrow deal.
public struct Escrow has key {
    id: UID,
    buyer: address,
    seller: address,
    amount: u64,
    status: u8,
}

/// Create a new escrow. Caller is the buyer; in production they must send amount as msg.value.
entry fun create(seller: address, amount: u64, ctx: &mut TxContext) {
    assert!(seller != ctx.sender(), 1);  // EBuyerIsSeller
    assert!(amount > 0, 2);               // EZeroAmount
    transfer::share_object(Escrow {
        id: object::new(ctx),
        buyer: ctx.sender(),
        seller,
        amount,
        status: PENDING,
    });
}

/// Seller confirms: release funds to seller.
#[ext(shared_objects(escrow))]
entry fun release(escrow: &mut Escrow, ctx: &TxContext) {
    assert!(escrow.status == PENDING, 3);
    assert!(ctx.sender() == escrow.seller, 4);
    escrow.status = RELEASED;
}

/// Buyer cancels: refund to buyer.
#[ext(shared_objects(escrow))]
entry fun refund(escrow: &mut Escrow, ctx: &TxContext) {
    assert!(escrow.status == PENDING, 3);
    assert!(ctx.sender() == escrow.buyer, 5);
    escrow.status = REFUNDED;
}

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
entry fun is_pending(escrow: &Escrow): bool {
    escrow.status == PENDING
}

//
// Unit tests
//
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
    };

    assert!(e.buyer() == @0x1, 0);
    assert!(e.seller() == @0x2, 0);
    assert!(e.amount() == 100, 0);
    assert!(e.is_pending(), 0);

    test_scenario::drop_storage_object(e);
}

#[test]
fun test_release_by_seller() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x2);
    let uid = object::new(&mut ctx);
    let mut e = Escrow { id: uid, buyer: @0x1, seller: @0x2, amount: 50, status: PENDING };

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
    let mut e = Escrow { id: uid, buyer: @0x1, seller: @0x2, amount: 75, status: PENDING };

    e.refund(&ctx);
    assert!(e.status() == REFUNDED, 0);
    assert!(!e.is_pending(), 0);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_release_by_non_seller_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x99);
    let uid = object::new(&mut ctx);
    let mut e = Escrow { id: uid, buyer: @0x1, seller: @0x2, amount: 100, status: PENDING };

    e.release(&ctx);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_refund_by_non_buyer_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x99);
    let uid = object::new(&mut ctx);
    let mut e = Escrow { id: uid, buyer: @0x1, seller: @0x2, amount: 100, status: PENDING };

    e.refund(&ctx);

    test_scenario::drop_storage_object(e);
}

#[test, expected_failure]
fun test_release_after_refund_fails() {
    let mut ctx = test_scenario::new_tx_context();
    test_scenario::set_sender_address(@0x1);
    let uid = object::new(&mut ctx);
    let mut e = Escrow { id: uid, buyer: @0x1, seller: @0x2, amount: 100, status: PENDING };
    e.refund(&ctx);

    test_scenario::set_sender_address(@0x2);
    e.release(&ctx);

    test_scenario::drop_storage_object(e);
}
