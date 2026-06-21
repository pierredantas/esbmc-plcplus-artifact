/*
 * motor_simple.c — D1 ST benchmark for ESBMC-PLC+ (ESBMC-PLC+ paper, Sec. V-A)
 *
 * Pre-generated scan-cycle harness for motor_sequencing.st (Listings 3-4).
 * Produced by wrapping MATIEC-generated C with nondeterministic input sampling
 * and __ESBMC_assert property injection (Section IV-B of the paper).
 *
 * Timer model: 1-bit delay (TON with PT = 1 scan-period, equivalent to T#2s
 * at 2 s/scan or T#10ms at 10 ms/scan for fast simulation).  _timer_armed
 * captures whether IN was TRUE in the previous scan; Q fires in the scan AFTER
 * the first IN=TRUE scan, which is the minimum cycle required to reproduce the
 * two-scan race condition described in the paper.
 *
 * Properties:
 *   P1 mutual_exclusion(Motor_A, Motor_B)  SAFE   → see motor_simple_p1.c
 *   P2 absence(Motor_B AND NOT Motor_A)    VIOLATION at k=2
 *
 * Verify P2 (VIOLATION) with:
 *   esbmc motor_simple.c --incremental-bmc --z3 --no-div-by-zero-check \
 *                        --no-pointer-check --no-align-check
 * Expected: VERIFICATION FAILED — Bug found (k = 2)
 */

#include <stdbool.h>

extern _Bool nondet_bool(void);

/* Persistent process-image state */
static _Bool Motor_A      = 0;   /* %QX0.0 */
static _Bool Motor_B      = 0;   /* %QX0.1 */
static _Bool _timer_armed = 0;   /* TON: IN was TRUE in the previous scan */

int main(void) {
    Motor_A      = 0;
    Motor_B      = 0;
    _timer_armed = 0;

    while (1) {
        /* 1. Input scan */
        _Bool Start = nondet_bool();   /* %IX0.0 */
        _Bool Stop  = nondet_bool();   /* %IX0.1 */

        /* TON Q: fires when IN was already TRUE last scan */
        _Bool _timer_q = _timer_armed;

        /* 2. Program body */
        if (Stop) {
            Motor_A      = 0;
            Motor_B      = 0;
            _timer_armed = 0;
        } else if (Start) {
            /* IF NOT Motor_B THEN Motor_A := TRUE; Timer(IN:=TRUE); END_IF */
            if (!Motor_B) {
                Motor_A      = 1;
                _timer_armed = 1;
            }
            /* IF Timer.Q THEN Motor_A := FALSE; Motor_B := TRUE; END_IF
             *
             * Race condition: on scan 2, _timer_q=TRUE (from scan-1 arming).
             * The IF NOT Motor_B block above just set Motor_A=TRUE, but then
             * this block immediately sets Motor_A=FALSE and Motor_B=TRUE.
             * Scan-end state: Motor_B=TRUE, Motor_A=FALSE → P2 violated. */
            if (_timer_q) {
                Motor_A = 0;
                Motor_B = 1;
            }
        }

        /* 3. P2: absence(Motor_B AND NOT Motor_A) — expected VIOLATION at k=2 */
        __ESBMC_assert(!(Motor_B && !Motor_A),
            "P2: Motor_B must not be active while Motor_A is inactive");
    }
    return 0;
}
