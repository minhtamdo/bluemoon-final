from django import forms
from .models import *

class FeeForm(forms.ModelForm):
    class Meta:
        model = Fee
        fields = ['title', 'description', 'type', 'amount', 'due_date']
