from django.apps import AppConfig

class ResidentsConfig(AppConfig):
    name = 'residents'

    def ready(self):
        import residents.signalsS

class CoreConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'core'