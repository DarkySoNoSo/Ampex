from ampex.engine.settings import load_latest_settings, settings_as_dict

def main():
    s = load_latest_settings()
    print("Latest bot_settings loaded ✅")
    print(settings_as_dict(s))

if __name__ == "__main__":
    main()
