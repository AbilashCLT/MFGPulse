# TC-08 Persona Access Validation
EXPECTED_ACCESS = {
    "TECHNICIAN": {"maintenance", "wo_po", "operations", "procurement", "copilot"},
    "RELIABILITY_ENGINEER": {"maintenance", "digital_twin", "wo_po", "operations", "procurement", "copilot"},
    "SHIFT_SUPERVISOR": {"operations", "wo_po", "maintenance", "procurement", "executive", "copilot"},
    "PLANT_MANAGER": {"executive", "operations", "wo_po", "maintenance", "procurement", "admin", "copilot"},
    "PROCUREMENT_ADMIN": {"procurement", "wo_po", "maintenance", "operations", "copilot"},
    "APP_ADMIN": {"executive", "operations", "wo_po", "maintenance", "procurement", "digital_twin", "admin", "copilot"},
}
ALL_PAGES = {"executive", "operations", "wo_po", "maintenance", "procurement", "digital_twin", "admin", "copilot"}

def run_tests():
    import sys, os
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'failure-genome-dashboard'))
    from app_pages._shared import PERSONA_CONFIG
    results = []
    results.append({"id": "TC-08-01", "name": "6 personas defined", "status": "PASS" if len(PERSONA_CONFIG)==6 else "FAIL"})
    results.append({"id": "TC-08-02", "name": "All have copilot", "status": "PASS" if all("copilot" in c["pages"] for c in PERSONA_CONFIG.values()) else "FAIL"})
    results.append({"id": "TC-08-03", "name": "Admin restricted", "status": "PASS" if set(k for k,v in PERSONA_CONFIG.items() if "admin" in v["pages"])=={"PLANT_MANAGER","APP_ADMIN"} else "FAIL"})
    results.append({"id": "TC-08-04", "name": "All have wo_po", "status": "PASS" if all("wo_po" in c["pages"] for c in PERSONA_CONFIG.values()) else "FAIL"})
    results.append({"id": "TC-08-06", "name": "APP_ADMIN all 8", "status": "PASS" if set(PERSONA_CONFIG["APP_ADMIN"]["pages"])==ALL_PAGES else "FAIL"})
    for persona, expected in EXPECTED_ACCESS.items():
        actual = set(PERSONA_CONFIG[persona]["pages"])
        results.append({"id": f"TC-08-{persona[:4]}", "name": f"{persona} access", "status": "PASS" if actual==expected else "FAIL"})
    return results

if __name__ == "__main__":
    for r in run_tests():
        print(f"[{r['status']}] {r['id']}: {r['name']}")
