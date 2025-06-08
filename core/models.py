from django.db import models
import uuid

# --- ENUMS ---
STATUS = [
    ('active', 'Active'),
    ('inactive', 'Inactive'),
]

STATUS_ACCOUNT = [
    ('active', 'Active'),
    ('inactive', 'Inactive'),
]

USER_ROLE = [
    ('chu_ho', 'Head of Household'),
    ('thu_ky', 'Accountant'),
    ('to_truong', 'Group Leader'),
    ('to_pho', 'Vice Group Leader')
]

FEE_TYPE = [
    ('mandatory', 'Mandatory'),
    ('voluntary', 'Voluntary'),
]

PAYMENT_METHOD = [
    ('qr_code', 'QR'),
    ('cash', 'Cash'),
    ('card', 'Card'),
]

PAYMENT_STATUS = [
    ('paid', 'Paid'),
    ('unpaid', 'Unpaid'),
]

CHANGE_TYPE = [
    ('add_member', 'Add Member'),
    ('remove_member', 'Remove Member'),
    ('update_info', 'Update Info'),
    ('change_head','Change Household Head')
]

STATUS_REQUEST = [
    ('pending', 'Pending'),
    ('approved', 'Approved'),
    ('rejected', 'Rejected'),
]

GENDER = [
    ('male', 'Male'),
    ('female', 'Female'),
    ('other', 'Other'),
]

NOTIFICATION_TYPE = [
    ('fee_reminder', 'Fee Reminder'),
    ('request_status', 'Request Status'),
    ('system_announcement', 'System Announcement'),
]

REQUEST_TYPE_CHOICES = [
    ('temporary_absence', 'Tạm vắng'),
    ('temporary_residence', 'Tạm trú'),
]

# --- MODELS ---

class User(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='user_id')
    username = models.TextField()
    password_hash = models.TextField()
    role = models.CharField(max_length=20, choices=USER_ROLE)
    fullname = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_ACCOUNT)
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()

    class Meta:
        db_table = 'users'

    def __str__(self):
        return self.fullname


class Household(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='household_id')
    household_number = models.TextField()
    head = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='households', db_column='head_id')
    household_size = models.IntegerField(default=1)
    address = models.TextField()
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()

    class Meta:
        db_table = 'households'

    def __str__(self):
        return self.household_number


class HouseholdMember(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='member_id')
    household = models.ForeignKey(Household, on_delete=models.CASCADE, related_name='members', db_column='household_id')
    full_name = models.TextField()
    gender = models.CharField(max_length=10, choices=GENDER)
    other_name = models.TextField(blank=True, null=True)
    dob = models.DateField()
    place_of_birth = models.TextField(blank=True, null=True)
    native_place = models.TextField(blank=True, null=True)
    ethnic_group = models.TextField(blank=True, null=True)
    occupation = models.TextField(blank=True, null=True)
    place_of_work = models.TextField(blank=True, null=True)
    cccd = models.TextField(blank=True, null=True)
    issue_date = models.DateField(blank=True, null=True)
    issued_by = models.TextField(blank=True, null=True)
    relationship = models.TextField()
    is_temporary = models.BooleanField(default=False)
    note = models.TextField(blank=True, null=True)
    joined_at = models.DateField()

    class Meta:
        db_table = 'household_members'

    def __str__(self):
        return self.full_name


class Fee(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='fee_id')
    title = models.TextField()
    description = models.TextField(blank=True, null=True)
    type = models.CharField(max_length=20, choices=FEE_TYPE)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    due_date = models.DateField()
    is_common = models.BooleanField(default=True, db_column='is_common')
    households = models.ManyToManyField('Household', blank=True, related_name='private_fees', db_table='fee_households')
    created_by = models.ForeignKey(User, null=True, on_delete=models.SET_NULL, related_name='fees', db_column='created_by')
    created_at = models.DateTimeField()

    class Meta:
        db_table = 'fees'

    def __str__(self):
        return self.title


class Payment(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='payment_id')
    fee = models.ForeignKey(Fee, on_delete=models.CASCADE, related_name='payments', db_column='fee_id', null=True)
    household = models.ForeignKey(Household, on_delete=models.CASCADE, related_name='payments', db_column='household_id')
    paid_at = models.DateTimeField()
    method = models.CharField(max_length=20, choices=PAYMENT_METHOD)
    status = models.CharField(max_length=20, choices=PAYMENT_STATUS)

    class Meta:
        db_table = 'payments'


class HouseholdChange(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='change_id')
    household = models.ForeignKey(Household, on_delete=models.CASCADE, null=True, related_name='changes', db_column='household_id')
    change_type = models.CharField(max_length=20, choices=CHANGE_TYPE)
    description = models.TextField()
    requested_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='changes_requested', db_column='requested_by')
    approved_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='changes_approved', db_column='approved_by')
    status = models.CharField(max_length=20, choices=STATUS_REQUEST)
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()

    class Meta:
        db_table = 'household_changes'


class ResidencyRequest(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False, db_column='request_id')
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='residency_requests', db_column='user_id')
    request_type = models.CharField(max_length=30, choices=REQUEST_TYPE_CHOICES)
    from_date = models.DateField()
    to_date = models.DateField(blank=True, null=True)
    destination = models.TextField()
    origin = models.TextField()
    reason = models.TextField()
    status = models.CharField(max_length=20, choices=STATUS_REQUEST)
    created_at = models.DateTimeField()
    updated_at = models.DateTimeField()

    class Meta:
        db_table = 'residency_requests'

class Activity(models.Model):
    ACTION_CHOICES = [
        ('create_household', 'Đăng ký hộ khẩu mới'),
        ('update_household', 'Cập nhật hộ khẩu'),
        ('delete_household', 'Xóa hộ khẩu'),
        ('create_member', 'Đăng ký nhân khẩu mới'),
        ('update_member', 'Cập nhật nhân khẩu'),
        ('delete_member', 'Xóa nhân khẩu'),
        ('approve_request', 'Duyệt yêu cầu'),
        ('reject_request', 'Từ chối yêu cầu'),
    ]

    action = models.CharField(max_length=50, choices=ACTION_CHOICES)
    timestamp = models.DateTimeField(auto_now_add=True)
    detail = models.TextField()  # Nội dung như: "Đăng ký hộ khẩu mới - Căn A123"
    status = models.CharField(max_length=20, choices=[
        ('pending', 'Chờ duyệt'),
        ('success', 'Đã duyệt'),
        ('error', 'Từ chối')
    ], default='success')