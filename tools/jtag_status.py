"""Read-only: print the Titanium configuration status register over JTAG."""
import os
import sys

sys.path.append(os.path.join(os.environ['EFXDBG_HOME'], 'bin'))
sys.path.append(os.path.join(os.environ['EFXPGM_HOME'], 'bin'))
from efx_dbg.jcf import JtagChainEngine
from efx_pgm.efx_hw_common.manager import EfxFTDIHwConnectionManager
from efx_pgm.prog_detector import ProgDetector

url = sys.argv[1]
provider = EfxFTDIHwConnectionManager.get_controller(
    url, EfxFTDIHwConnectionManager.ConnectionType.JTAG)
engine = JtagChainEngine(devices=None, target_num=1, engine_provider=provider)
engine.configure(url=url)
engine.reset()
detector = ProgDetector(engine, devices=None)
print('IDCODE', detector.get_idcode())
try:
    print('PROG_STATE', detector.get_prog_state())
except Exception as exc:
    print('PROG_STATE unavailable:', exc)
for name, value in detector.get_device_registers(read_value=True).items():
    print(f"  {name:20s} {value['value']}")
try:
    print('USERCODE', detector.read_usercode())
except Exception as exc:
    print('USERCODE unavailable:', exc)
engine.close()
