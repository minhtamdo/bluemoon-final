from django.contrib import admin
from .models import (
    User, Household, HouseholdMember, Fee,
    Payment, HouseholdChange, ResidencyRequest
)


@admin.register(User)
class UserAdmin(admin.ModelAdmin):
    list_display = ('username', 'fullname', 'role', 'status', 'created_at')
    search_fields = ('username', 'fullname')
    list_filter = ('role', 'status')


@admin.register(Household)
class HouseholdAdmin(admin.ModelAdmin):
    list_display = ('household_number', 'head_fullname', 'household_size', 'address', 'created_at')
    search_fields = ('household_number', 'address')
    list_filter = ('household_size',)

    def head_fullname(self, obj):
        return obj.head.fullname if obj.head else "(None)"
    head_fullname.short_description = 'Head of Household'


@admin.register(HouseholdMember)
class HouseholdMemberAdmin(admin.ModelAdmin):
    list_display = ('full_name', 'household_number', 'gender', 'relationship', 'dob', 'joined_at')
    search_fields = ('full_name', 'household__household_number', 'cccd')
    list_filter = ('gender', 'is_temporary')

    def household_number(self, obj):
        return obj.household.household_number
    household_number.short_description = 'Household Number'


@admin.register(Fee)
class FeeAdmin(admin.ModelAdmin):
    list_display = (
        'title', 'type', 'amount', 'due_date',
        'is_common', 'household_list',
        'created_by_fullname', 'created_at',
    )
    search_fields = ('title',)
    list_filter = ('type', 'due_date', 'is_common')

    def created_by_fullname(self, obj):
        return obj.created_by.fullname if obj.created_by else "(None)"
    created_by_fullname.short_description = 'Created By'

    def household_list(self, obj):
        if obj.is_common:
            return "Tất cả"
        households = obj.households.all()
        if not households:
            return "(Không có)"
        return ", ".join(h.household_number for h in households)
    household_list.short_description = 'Áp dụng cho hộ'


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ('fee_title', 'household_number', 'paid_at', 'method', 'status')
    list_filter = ('method', 'status')

    def fee_title(self, obj):
        return obj.fee.title  # sửa từ fee_id thành fee
    fee_title.short_description = 'Fee Title'

    def household_number(self, obj):
        return obj.household.household_number  # sửa từ household_id thành household
    household_number.short_description = 'Household Number'


@admin.register(HouseholdChange)
class HouseholdChangeAdmin(admin.ModelAdmin):
    list_display = ('household_number', 'change_type', 'status', 'requested_by_fullname', 'approved_by_fullname', 'created_at')

    def household_number(self, obj):
        return obj.household.household_number  # sửa từ household_id thành household
    household_number.short_description = 'Household Number'

    def requested_by_fullname(self, obj):
        return obj.requested_by.fullname if obj.requested_by else "(None)"
    requested_by_fullname.short_description = 'Requested By'

    def approved_by_fullname(self, obj):
        return obj.approved_by.fullname if obj.approved_by else "(None)"
    approved_by_fullname.short_description = 'Approved By'


@admin.register(ResidencyRequest)
class ResidencyRequestAdmin(admin.ModelAdmin):
    list_display = ('user_fullname', 'request_type', 'from_date', 'to_date', 'destination', 'origin', 'status', 'created_at')

    def user_fullname(self, obj):
        return obj.user.fullname  # sửa từ user_id thành user
    user_fullname.short_description = 'User'
