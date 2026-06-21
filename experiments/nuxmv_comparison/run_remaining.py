#!/usr/bin/env python3
"""
run_remaining.py — Run only the benchmarks not yet completed, appending to CSV.
Starts from elevator_safe (bottle_filling results already in CSV).
"""
import os, sys, subprocess, time, csv, pathlib, re, yaml

SCRIPT_DIR  = pathlib.Path(__file__).parent
BENCH_DIR   = pathlib.Path('/Users/pierredantas/esbmc/benchmarks')
ESBMC       = '/Users/pierredantas/esbmc/build/src/esbmc/esbmc'
NUXMV       = '/tmp/nuXmv-2.2.0-macos64/usr/local/bin/nuXmv'
NUXMV_LIBS  = '/tmp/nuXmv-2.2.0-macos64/usr/local/lib'
TRANSPILER  = str(SCRIPT_DIR / 'ld_to_smv.py')
RESULTS_DIR = SCRIPT_DIR / 'results'
SMV_DIR     = RESULTS_DIR / 'smv'
TIMEOUT     = 120

BENCHMARKS = [
    ('elevator_safe',
     BENCH_DIR/'elevator/elevator_safe.ld',
     BENCH_DIR/'elevator/props.yaml', 'SAFE'),
    ('elevator_unsafe',
     BENCH_DIR/'elevator/elevator_unsafe.ld',
     BENCH_DIR/'elevator/props_unsafe.yaml', 'VIOLATION'),
    ('traffic_light_safe',
     BENCH_DIR/'traffic_light/traffic_light_safe.ld',
     BENCH_DIR/'traffic_light/props.yaml', 'SAFE'),
    ('traffic_light_unsafe',
     BENCH_DIR/'traffic_light/traffic_light_unsafe.ld',
     BENCH_DIR/'traffic_light/props.yaml', 'VIOLATION'),
]

FIELDS = [
    'benchmark', 'expected',
    'esbmc_verdict', 'esbmc_time_s',
    'nuxmv_bdd_verdict', 'nuxmv_bdd_time_s',
    'nuxmv_ic3_verdict', 'nuxmv_ic3_time_s',
    'num_bool_vars', 'num_int_vars', 'num_rungs', 'num_props',
]


def run_cmd(args, env=None, log_path=None):
    env_ = dict(os.environ)
    if env:
        env_.update(env)
    start = time.perf_counter()
    try:
        result = subprocess.run(
            args, capture_output=True, text=True,
            timeout=TIMEOUT, env=env_
        )
        elapsed = time.perf_counter() - start
        out = result.stdout + result.stderr
        if log_path:
            pathlib.Path(log_path).write_text(out)
        return elapsed, result.returncode, out
    except subprocess.TimeoutExpired as e:
        elapsed = time.perf_counter() - start
        def _dec(b):
            if b is None: return ''
            return b.decode('utf-8', errors='replace') if isinstance(b, bytes) else b
        out = _dec(e.stdout) + _dec(e.stderr)
        if log_path:
            pathlib.Path(log_path).write_text(out + '\n[TIMEOUT]')
        return elapsed, 124, out


def run_nuxmv(smv_path, mode, log_path):
    if mode == 'bdd':
        cmds = (f'read_model -i {smv_path}\n'
                'flatten_hierarchy\nencode_variables\nbuild_model\n'
                'check_invar\nquit\n')
    else:
        cmds = (f'read_model -i {smv_path}\n'
                'flatten_hierarchy\nencode_variables\nbuild_boolean_model\n'
                'check_invar_ic3\nquit\n')
    env_ = dict(os.environ)
    env_['DYLD_LIBRARY_PATH'] = NUXMV_LIBS
    start = time.perf_counter()
    try:
        result = subprocess.run(
            [NUXMV, '-int'], input=cmds,
            capture_output=True, text=True,
            timeout=TIMEOUT, env=env_
        )
        elapsed = time.perf_counter() - start
        out = result.stdout + result.stderr
        if log_path:
            pathlib.Path(log_path).write_text(out)
        return elapsed, result.returncode, out
    except subprocess.TimeoutExpired as e:
        elapsed = time.perf_counter() - start
        def _dec(b):
            if b is None: return ''
            return b.decode('utf-8', errors='replace') if isinstance(b, bytes) else b
        out = _dec(e.stdout) + _dec(e.stderr)
        if log_path:
            pathlib.Path(log_path).write_text(out + '\n[TIMEOUT]')
        return elapsed, 124, out


def esbmc_verdict(out):
    if 'VERIFICATION SUCCESSFUL' in out: return 'SAFE'
    if 'VERIFICATION FAILED' in out: return 'VIOLATION'
    return 'UNKNOWN'


def nuxmv_verdict(out, rc):
    if rc == 124: return 'TIMEOUT'
    if re.search(r'is false', out): return 'VIOLATION'
    if re.search(r'is true', out): return 'SAFE'
    return 'UNKNOWN'


def count_vars(ld_path):
    text = pathlib.Path(ld_path).read_text()
    return (len(re.findall(r'<BOOL/>', text)),
            len(re.findall(r'<(?:INT|DINT|UINT|WORD|BYTE)\/>', text)),
            len(re.findall(r'<rung\b', text)))


csv_path = RESULTS_DIR / 'results.csv'
# Append to existing CSV
with open(csv_path, 'a', newline='') as csvf:
    writer = csv.DictWriter(csvf, fieldnames=FIELDS)

    for (label, ld_path, props_path, expected) in BENCHMARKS:
        ld_path    = pathlib.Path(ld_path)
        props_path = pathlib.Path(props_path)
        print(f'\n{"═"*60}')
        print(f'  {label}  (expected: {expected})')

        bool_cnt, int_cnt, rung_cnt = count_vars(ld_path)
        with open(props_path) as f:
            prop_cnt = len(yaml.safe_load(f).get('properties', []))
        print(f'  BOOL={bool_cnt} INT={int_cnt} Rungs={rung_cnt} Props={prop_cnt}')

        # Transpile
        smv_path = str(SMV_DIR / f'{label}.smv')
        tp_e, tp_rc, _ = run_cmd(
            ['python3', TRANSPILER, str(ld_path), str(props_path), '--out', smv_path])
        smv_ok = tp_rc == 0 and pathlib.Path(smv_path).exists()
        print(f'  [SMV] {"OK" if smv_ok else "FAIL"} ({tp_e:.2f}s)')

        # ESBMC
        esbmc_log = str(RESULTS_DIR / f'{label}_esbmc.log')
        elapsed_e, rc_e, out_e = run_cmd(
            [ESBMC, str(ld_path), '--ld-props', str(props_path),
             '--k-induction', '--z3', '--no-div-by-zero-check'],
            log_path=esbmc_log)
        v_esbmc = 'TIMEOUT' if rc_e == 124 else esbmc_verdict(out_e)
        print(f'  [ESBMC]      {v_esbmc:10s}  {elapsed_e:.3f}s')

        # NuXmv BDD
        elapsed_b, v_bdd = 0.0, 'N/A'
        if smv_ok:
            bdd_log = str(RESULTS_DIR / f'{label}_nuxmv_bdd.log')
            elapsed_b, rc_b, out_b = run_nuxmv(smv_path, 'bdd', bdd_log)
            v_bdd = nuxmv_verdict(out_b, rc_b)
            print(f'  [NuXmv BDD]  {v_bdd:10s}  {elapsed_b:.3f}s')

        # NuXmv IC3
        elapsed_i, v_ic3 = 0.0, 'N/A'
        if smv_ok:
            ic3_log = str(RESULTS_DIR / f'{label}_nuxmv_ic3.log')
            elapsed_i, rc_i, out_i = run_nuxmv(smv_path, 'ic3', ic3_log)
            v_ic3 = nuxmv_verdict(out_i, rc_i)
            print(f'  [NuXmv IC3]  {v_ic3:10s}  {elapsed_i:.3f}s')

        writer.writerow({
            'benchmark': label, 'expected': expected,
            'esbmc_verdict': v_esbmc, 'esbmc_time_s': f'{elapsed_e:.3f}',
            'nuxmv_bdd_verdict': v_bdd,
            'nuxmv_bdd_time_s': f'{elapsed_b:.3f}',
            'nuxmv_ic3_verdict': v_ic3,
            'nuxmv_ic3_time_s': f'{elapsed_i:.3f}',
            'num_bool_vars': bool_cnt, 'num_int_vars': int_cnt,
            'num_rungs': rung_cnt, 'num_props': prop_cnt,
        })
        csvf.flush()

print(f'\nDone. Results in: {csv_path}')

# Generate LaTeX table
result = subprocess.run(
    ['python3', str(SCRIPT_DIR / 'make_table.py'), str(csv_path)],
    capture_output=True, text=True)
tex_path = RESULTS_DIR / 'results_table.tex'
tex_path.write_text(result.stdout)
print(f'LaTeX table: {tex_path}')
