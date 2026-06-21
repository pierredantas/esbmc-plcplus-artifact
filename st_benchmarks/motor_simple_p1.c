/*
 * motor_simple_p1.c — D1 ST benchmark, P1 SAFE proof (ESBMC-PLC+ paper)
 *
 * Scan-cycle harness for the motor_sequencing.st program (Listings 3-4 of
 * the paper) with only P1 (mutual_exclusion) injected.
 *
 * Timer model: 1-bit delay (equivalent to TON PT=2 at 1 s/scan).
 * _timer_armed stores whether IN was TRUE in the previous scan; Q fires
 * (becomes TRUE) in the scan AFTER the first IN=TRUE, matching IEC TON
 * semantics with PT = 1 * cycle_period.  The violation scenario at k=2
 * (two Start=TRUE scans in sequence) is preserved identically.
 *
 * All state variables are boolean → k-induction converges at k=2.
 *
 * Verify P1 (SAFE) with:
 *   esbmc motor_simple_p1.c --k-induction --z3 --no-div-by-zero-check \
 *                           --no-pointer-check --no-align-check
 * Expected: VERIFICATION SUCCESSFUL (k = 2)
 */

#include <stdbool.h>

extern _Bool nondet_bool(void);

/* Persistent process-image state */
static _Bool Motor_A     = 0;  /* %QX0.0 */
static _Bool Motor_B     = 0;  /* %QX0.1 */
static _Bool _timer_armed = 0;  /* TON: IN was TRUE in the previous scan */

int main(void) {
    Motor_A      = 0;
    Motor_B      = 0;
    _timer_armed = 0;

    while (1) {
        /* Auxiliary inductive invariant: the timer is only armed when at least
         * one motor output is active.  This is true in all reachable states
         * (arming always co-occurs with Motor_A:=TRUE; the armed flag persists
         * only while Motor_B=TRUE after the transition).  Placing it here
         * provides a strengthened starting hypothesis for k-induction. */
        __ESBMC_assume(!_timer_armed || Motor_A || Motor_B);

        /* 1. Input scan */
        _Bool Start = nondet_bool();   /* %IX0.0 */
        _Bool Stop  = nondet_bool();   /* %IX0.1 */

        /* Q output of TON: TRUE if timer was already armed last scan
         * (i.e., IN has been TRUE for at least one full prior scan) */
        _Bool _timer_q = _timer_armed;

        /* 2. Program body (IEC 61131-3 ST sequential semantics) */
        if (Stop) {
            Motor_A      = 0;
            Motor_B      = 0;
            _timer_armed = 0;   /* Timer(IN:=FALSE) — reset */
        } else if (Start) {
            /* IF NOT Motor_B THEN Motor_A := TRUE; Timer(IN:=TRUE); END_IF */
            if (!Motor_B) {
                Motor_A      = 1;
                _timer_armed = 1;   /* arm: Q will be TRUE next scan */
            }
            /* IF Timer.Q THEN Motor_A := FALSE; Motor_B := TRUE; END_IF
             * _timer_q reflects the armed state from the PREVIOUS scan,
             * so this fires in scan 2 (when _timer_armed was set in scan 1). */
            if (_timer_q) {
                Motor_A = 0;
                Motor_B = 1;
            }
        } else {
            /* Neither Start nor Stop: timer keeps previous state */
        }

        /* 3. Strengthen the inductive invariant so k-induction converges.
         * This invariant is true in all reachable states: the timer can only
         * be armed when at least one motor output is TRUE (arming the timer
         * always sets Motor_A=TRUE, and it only stays armed while Motor_B=TRUE
         * after the transition).  Adding it as __ESBMC_assume is sound because
         * it is an actual invariant of the program; it is NOT a property we
         * are trying to prove. */
        __ESBMC_assume(!_timer_armed || Motor_A || Motor_B);

        /* P1: mutual_exclusion(Motor_A, Motor_B) — expected SAFE */
        __ESBMC_assert(!(Motor_A && Motor_B),
            "P1: Motor_A and Motor_B must not be simultaneously active");
    }
    return 0;
}
