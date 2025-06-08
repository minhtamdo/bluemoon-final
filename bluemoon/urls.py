"""
URL configuration for bluemoon project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from django.shortcuts import render
from core.models import *  # sửa lại path import theo app của bạn
from django.utils import timezone
from django.db.models import Sum, Q, Value, Min, DecimalField
from django.db.models.functions import Coalesce
from datetime import datetime, time, timedelta, date
from django.http import JsonResponse, HttpResponse, HttpResponseBadRequest, HttpResponseNotAllowed
from core.forms import FeeForm
import calendar
from openpyxl import Workbook 
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from django.shortcuts import redirect, get_object_or_404
import json
from django.db import connection
from django.shortcuts import redirect
from django.conf import settings
import stripe
import traceback
from django.utils.timezone import now
import logging
from django.views.decorators.http import require_POST
from django.views.decorators.http import require_http_methods
import io
from collections import defaultdict
from django.dispatch import receiver
from django.db.models.signals import post_save, post_delete
from django.db.models import Count

stripe.api_key = settings.STRIPE_SECRET_KEY
logger = logging.getLogger(__name__)

@csrf_exempt
def cudan_view(request):
    if not request.session.get('user_id') or request.session.get('role') != 'chu_ho':
        return redirect('/login')

    user_id = request.session['user_id']
    household = Household.objects.filter(head__id=user_id).first()

    if not household:
        return render(request, 'error.html', {'message': 'Không tìm thấy thông tin hộ dân.'})

    today = date.today()

    fees = Fee.objects.filter(
        (Q(is_common=True) | Q(households=household))
    ).distinct()

    # Lấy tất cả bản ghi Payment liên quan
    all_payments = Payment.objects.filter(
        household=household,
        fee__in=fees
    )

    total_fee = fees.aggregate(
        total=Coalesce(Sum('amount'), Value(0), output_field=DecimalField())
    )['total']

    paid_total = all_payments.filter(status='paid').aggregate(
        total=Coalesce(Sum('fee__amount'), Value(0), output_field=DecimalField())
    )['total']

    unpaid_total = total_fee - paid_total if total_fee else 0

    due_date = fees.aggregate(
        soonest=Min('due_date')
    )['soonest']

    # Tạo danh sách khoản phí kèm payment.id (nếu có)
    fee_status_list = []
    for fee in fees:
        payment = all_payments.filter(fee=fee).first()
        fee_status_list.append({
            'fee_id': str(fee.id),
            'payment_id': str(payment.id) if payment else '',
            'title': fee.title,
            'amount': fee.amount,
            'status': payment.status if payment else 'unpaid'
        })

    user = User.objects.get(id=user_id)

    # Lịch sử yêu cầu
    request_history = ResidencyRequest.objects.filter(user=user).order_by('-created_at')

    # Lịch sử thanh toán (chỉ lấy payment đã paid)
    payment_history = Payment.objects.filter(household=household, status='paid').select_related('fee').order_by('-paid_at')

    return render(request, 'homeowner.html', {
        'fullname': household.head.fullname,
        'apartment_number': household.household_number,
        'total_fee': total_fee,
        'paid_total': paid_total,
        'unpaid_total': unpaid_total,
        'due_date': due_date,
        'fee_status_list': fee_status_list,
        'request_history': request_history,
        'payment_history': payment_history,
    })

@csrf_exempt
def fee_detail_api(request, fee_id):
    fee = get_object_or_404(Fee, pk=fee_id)

    if request.method == 'GET':
        return JsonResponse({
            'id': str(fee.id),
            'title': fee.title,
            'amount': fee.amount,
            'type': fee.type,
            'due_date': fee.due_date.strftime('%Y-%m-%d'),
            'description': fee.description,
        })

    elif request.method == 'PUT':
        try:
            data = json.loads(request.body)
            allowed_fields = ['title', 'amount', 'type', 'due_date', 'description']

            for field in allowed_fields:
                if field in data:
                    setattr(fee, field, data[field])
            fee.save()
            return JsonResponse({'success': True})
        except Exception as e:
            return HttpResponseBadRequest(f"Lỗi: {str(e)}")

    else:
        return HttpResponseNotAllowed(['GET', 'PUT'])

@csrf_exempt  # hoặc bạn có thể dùng CSRF token hợp lệ, không bỏ decorator nếu có token
def delete_fee(request, fee_id):
    if request.method == 'POST':
        fee = get_object_or_404(Fee, pk=fee_id)
        fee.delete()
        return JsonResponse({'message': 'Xóa khoản phí thành công'})
    else:
        return HttpResponseNotAllowed(['POST'])

@csrf_exempt
def create_checkout_session(request):
    if request.method != 'POST':
        return HttpResponseBadRequest("Invalid method")

    try:
        data = json.loads(request.body)
        payment_id = data.get('payment_id')  # frontend gửi key này

        payment = Payment.objects.get(id=payment_id)

        session = stripe.checkout.Session.create(
            payment_method_types=['card'],
            line_items=[{
                'price_data': {
                    'currency': 'usd',
                    'product_data': {
                        'name': f'Thanh toán phí: {payment.fee.title}',
                    },
                    'unit_amount': int(payment.fee.amount * 100),  # USD -> cents
                },
                'quantity': 1,
            }],
            mode='payment',
            success_url=request.build_absolute_uri('/payment-success/'),
            cancel_url=request.build_absolute_uri('/payment-cancelled/'),
            metadata={
                'payment_id': str(payment.id)
            }
        )

        return JsonResponse({'url': session.url})

    except Payment.DoesNotExist:
        return HttpResponseBadRequest("Không tìm thấy payment.")
    except Exception as e:
        logger.error(f"Error creating Stripe checkout session: {e}")
        return JsonResponse({'error': str(e)}, status=500)


@csrf_exempt
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE')
    endpoint_secret = settings.STRIPE_WEBHOOK_SECRET

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, endpoint_secret)
    except ValueError as e:
        logger.error(f'Invalid payload: {e}')
        return HttpResponse(status=400)
    except stripe.error.SignatureVerificationError as e:
        logger.error(f'Signature verification failed: {e}')
        return HttpResponse(status=400)

    logger.info(f'Received Stripe event: {event["type"]}')

    if event['type'] == 'checkout.session.completed':
        session = event['data']['object']
        payment_id = session['metadata'].get('payment_id')

        logger.info(f'Checkout session completed for payment_id: {payment_id}')
        try:
            payment = Payment.objects.get(id=payment_id)
            payment.status = 'paid'
            payment.paid_at = timezone.now()
            payment.method = 'card'
            payment.save()
            logger.info(f'Payment {payment_id} updated to paid')
        except Payment.DoesNotExist:
            logger.error(f'Payment with id {payment_id} does not exist')

    return HttpResponse(status=200)

@csrf_exempt
def login_view(request):
    
    if request.method == 'GET':
        return render(request, 'dangnhap.html')

    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            username = data.get('username')
            password = data.get('password')
            role_input = data.get('role')

            role_map = {
                'resident': 'chu_ho',
                'leader': ['to_truong', 'to_pho'],
                'accountant': 'thu_ky'
            }
            allowed_roles = role_map.get(role_input)
            if isinstance(allowed_roles, str):
                allowed_roles = [allowed_roles]
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT user_id, username, fullname, role
                    FROM users
                    WHERE username = %s
                    AND role IN %s
                    AND password_hash = crypt(%s, password_hash)
                    AND status = 'active'
                """, [username, tuple(allowed_roles), password])
                row = cursor.fetchone()

            if row:
                # ✔️ Lưu trạng thái đăng nhập
                request.session['user_id'] = str(row[0])
                request.session['username'] = row[1]
                request.session['fullname'] = row[2]
                request.session['role'] = row[3]

                return JsonResponse({
                    'success': True,
                    'redirect_url': get_redirect_url(row[3]),
                    'user': {'fullname': row[2], 'username': row[1], 'role': row[3]}
                })
            else:
                return JsonResponse({'success': False, 'message': 'Sai tài khoản, mật khẩu hoặc vai trò không hợp lệ.'})
        except Exception as e:
            return JsonResponse({'success': False, 'message': str(e)})
    return JsonResponse({'success': False, 'message': 'Chỉ hỗ trợ POST'})

def logout_view(request):
    request.session.flush()  
    return redirect('/login')

def get_redirect_url(role):
    if role == 'chu_ho':
        return '/cudan'
    elif role in ['to_truong', 'to_pho']:
        return '/leader'
    elif role == 'thu_ky':
        return '/ketoan'
    return '/login'

    # KE TOAN
    @csrf_exempt
    def ketoan_view(request):
        if not request.session.get('user_id') or request.session.get('role') != 'thu_ky':
            return redirect('/login')
        if request.method == 'GET' and request.headers.get('x-requested-with') == 'XMLHttpRequest' and 'month' in request.GET:
            month_str = request.GET.get("month")
            try:
                year, month = map(int, month_str.split("-"))
                start_date = date(year, month, 1)
                last_day = calendar.monthrange(year, month)[1]
                end_date = date(year, month, last_day)
            except Exception as e:
                print("Lỗi khi parse tháng:", e)
                return HttpResponse("Tháng không hợp lệ", status=400)

            fees = Fee.objects.filter(due_date__range=(start_date, end_date)).order_by('due_date')

            wb = Workbook()
            ws = wb.active
            ws.title = "Báo cáo phí"
            ws.append(["Căn hộ", "Loại phí", "Số tiền", "Hạn đóng", "Trạng thái", "Ngày thanh toán"])

            for fee in fees:
                payments = fee.payments.all()
                for payment in payments:
                    ws.append([
                        payment.household.household_number,
                        fee.title,
                        float(fee.amount),
                        fee.due_date.strftime("%d/%m/%Y"),
                        payment.get_status_display(),
                        payment.paid_at.strftime("%d/%m/%Y %H:%M") if payment.paid_at else ''
                    ])

            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            filename = f"bao_cao_phi_{year}_{month:02}.xlsx"
            response['Content-Disposition'] = f'attachment; filename="{filename}"'
            wb.save(response)
            return response

        # Tổng số chủ hộ
        total_residents = User.objects.filter(role='chu_ho').count()
        now = timezone.localtime(timezone.now())
        today = now.date()

        # Xác định mốc thời gian
        start_of_this_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        if now.month == 12:
            start_of_next_month = start_of_this_month.replace(year=now.year + 1, month=1)
        else:
            start_of_next_month = start_of_this_month.replace(month=now.month + 1)

        if now.month == 1:
            start_of_last_month = start_of_this_month.replace(year=now.year - 1, month=12)
        else:
            start_of_last_month = start_of_this_month.replace(month=now.month - 1)

        # Tổng doanh thu tháng này
        total_revenue = Payment.objects.filter(
            paid_at__gte=start_of_this_month,
            paid_at__lt=start_of_next_month,
            status='paid'
        ).aggregate(total=Sum('fee__amount'))['total'] or 0

        # Doanh thu tháng trước
        last_month_revenue = Payment.objects.filter(
            paid_at__gte=start_of_last_month,
            paid_at__lt=start_of_this_month,
            status='paid'
        ).aggregate(total=Sum('fee__amount'))['total'] or 0

        # Tính phần trăm thay đổi
        if last_month_revenue == 0:
            change_percent = None
        else:
            change_percent = ((total_revenue - last_month_revenue) / last_month_revenue) * 100

        # Đã thanh toán trong tháng này
        paid_count = Payment.objects.filter(
            paid_at__gte=start_of_this_month,
            paid_at__lt=start_of_next_month,
            status='paid'
        ).count()

        # Chưa thanh toán trong tháng này
        unpaid_count = Payment.objects.filter(
            paid_at__gte=start_of_this_month,
            paid_at__lt=start_of_next_month,
            status='unpaid'
        ).count()

        # Tổng phí cần thu trong tháng
        total_due = Fee.objects.filter(
            due_date__gte=start_of_this_month,
            due_date__lt=start_of_next_month
        ).aggregate(total=Sum('amount'))['total'] or 0

        # Tỷ lệ thu
        collection_rate = (total_revenue / total_due) * 100 if total_due > 0 else None

        # Lấy danh sách nhân khẩu
        members = HouseholdMember.objects.all()

        # Lấy số hoá đơn quá hạn
        overdue_bills = Fee.objects.filter(
        due_date__lt=today
        ).exclude(
        payments__status='paid'
        ).distinct().count()

        # Tổng nợ: các hóa đơn quá hạn chưa thanh toán
        paid_subquery = Payment.objects.filter(
        fee=OuterRef('pk'),
        status='paid'
        )

        total_debt = Fee.objects.filter(
            due_date__lt=today
        ).annotate(
            has_paid=Exists(paid_subquery)
        ).filter(
            has_paid=False
        ).aggregate(
            total=Sum('amount')
        )['total'] or 0

        households_need_contact = Household.objects.filter(
        payments__fee__due_date__lt=today,
        payments__status='unpaid'
        ).distinct()

        need_contact_count = households_need_contact.count()
        fees = Fee.objects.all()
        payments = Payment.objects.select_related('fee', 'household').all()
        for payment in payments:
            if payment.paid_at:
                payment.paid_at_vn = payment.paid_at + timedelta(hours=7)
            else:
                payment.paid_at_vn = None

        households = Household.objects.all()
        form = FeeForm()
        if request.method == 'POST' and request.headers.get('x-requested-with') == 'XMLHttpRequest':
            form = FeeForm(request.POST)
            if form.is_valid():
                user_id = request.session.get('user_id')
                if not user_id:
                    return JsonResponse({'success': False, 'message': 'Người dùng chưa đăng nhập.'}, status=403)

                try:
                    user = User.objects.get(id=user_id)
                except User.DoesNotExist:
                    return JsonResponse({'success': False, 'message': 'Không tìm thấy người dùng.'}, status=404)

                fee = form.save(commit=False)
                fee.created_by = user
                fee.created_at = datetime.now()

                # Xử lý phí chung hay riêng
                is_common = request.POST.get('is_common', 'true') == 'true'
                fee.is_common = is_common
                fee.save()

                if not is_common:
                    household_ids = request.POST.getlist('households') # Nếu cần import
                    households = Household.objects.filter(id__in=household_ids)
                    fee.households.set(households)  # thiết lập quan hệ N-N

                return JsonResponse({
                    'success': True,
                    'id': str(fee.id),
                    'title': fee.title,
                    'amount': float(fee.amount),
                    'type': fee.type,
                    'due_date': fee.due_date.strftime('%Y-%m-%d'),
                    'description': fee.description or '',
                    'is_common': fee.is_common
                })
            return JsonResponse({'success': False, 'errors': form.errors}, status=400)

        # Nếu là GET, render trang kế toán
        if not request.session.get('user_id') or request.session.get('role') != 'thu_ky':
            return redirect('/login')
        
        if request.method == 'GET' and request.headers.get('x-requested-with') == 'XMLHttpRequest' and request.GET.get('debt') == '1':

            today = now.date()

            unpaid_payments = Payment.objects.filter(
                status='unpaid',
                fee__due_date__lt=today
            ).select_related('fee', 'household__head')

            wb1 = Workbook()
            ws1 = wb1.active
            ws1.title = "Danh sách nợ"

            ws1.append(["Căn hộ", "Chủ hộ", "Loại phí", "Số tiền", "Hạn đóng"])

            for payment in unpaid_payments:
                household = payment.household
                head_name = household.head.fullname if household and household.head else "Không rõ"
                fee = payment.fee
                ws1.append([
                    household.household_number,
                    head_name,
                    fee.title,
                    float(fee.amount),
                    fee.due_date.strftime("%d/%m/%Y")
                ])

            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = 'attachment; filename="danh_sach_no.xlsx"'
            wb1.save(response)
            return response
        user_id = request.session.get('user_id')
        user = User.objects.get(id=user_id)


        return render(request, 'ketoan.html', {
            'total_residents': total_residents,
            'total_revenue': total_revenue,
            'change_percent': change_percent,
            'paid_count': paid_count,
            'unpaid_count': unpaid_count,
            'collection_rate': collection_rate,
            'members': members,
            'overdue_bills': overdue_bills,
            'total_debt' : total_debt,
            'need_contact_count': need_contact_count,
            'fees': fees,
            'payments': payments,
            'fullname': user.fullname,
            'households': households,
            'form': form,
        })

def update_payment(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            payment_id = data.get('payment_id')
            paid_at = data.get('paid_at')
            status = data.get('status')
            method = data.get('method')

            payment = Payment.objects.get(id=payment_id)
            payment.paid_at = paid_at
            payment.status = status
            payment.method = method
            payment.save()

            return JsonResponse({'success': True})
        except Payment.DoesNotExist:
            return JsonResponse({'success': False, 'error': 'Payment không tồn tại'})
        except Exception as e:
            return JsonResponse({'success': False, 'error': str(e)})

    return JsonResponse({'success': False, 'error': 'Phương thức không hợp lệ'})

def revenue_pie_data(request):
    now = timezone.localtime(timezone.now())
    today = now.date()
    current_month = today.month
    current_year = today.year

    data = (
        Payment.objects
        .filter(
            status='paid',
            paid_at__year=current_year,
            paid_at__month=current_month
        )
        .values(title=F('fee__title'))
        .annotate(total=Sum('fee__amount'))
    )

    total_amount = sum(item['total'] for item in data)
    response_data = [
        {
            'title': item['title'],
            'value': round(item['total'] / total_amount * 100, 1) if total_amount > 0 else 0
        } for item in data
    ]

    return JsonResponse(response_data, safe=False)


def payment_success(request):
    payment_id = request.session.pop('pending_payment_id', None)
    if payment_id:
        try:
            payment = Payment.objects.get(id=payment_id)
            payment.status = 'paid'
            payment.method = 'card'
            payment.paid_at = now()
            payment.save()
        except Payment.DoesNotExist:
            return render(request, 'error.html', {'message': 'Không tìm thấy bản ghi thanh toán.'})

    return render(request, 'payment_success.html')

def payment_cancel(request):
    return render(request, 'payment_cancel.html')

@csrf_exempt
@require_POST
def submit_residency_request(request):
    try:
        # Lấy user_id từ session
        user_id = request.session.get('user_id')
        if not user_id:
            return JsonResponse({"error": "Bạn chưa đăng nhập."}, status=403)
        
        # Lấy User instance từ DB (model của bạn)
        user = get_object_or_404(User, id=user_id)

        data = json.loads(request.body)

        ResidencyRequest.objects.create(
            user=user,  # Gán user của bạn
            request_type=data.get("request_type"),
            from_date=data.get("from_date"),
            to_date=data.get("to_date"),
            origin=data.get("origin"),
            destination=data.get("destination"),
            reason=data.get("reason"),
            status='pending',
            created_at=now(),
            updated_at=now()
        )
        return JsonResponse({"message": "Đã gửi yêu cầu thành công."})

    except Exception as e:
        return JsonResponse({"error": str(e)}, status=400)


urlpatterns = [
    path('login/', login_view, name='home'), 
    path('logout/', logout_view, name='logout'),  
    path('admin/', admin.site.urls),
    path('ketoan/', ketoan_view, name='ketoan'),
    path('cudan/', cudan_view, name='cudan'),
    path('update_payment/', update_payment, name='update_payment'),
    path('revenue_pie_data/', revenue_pie_data, name='revenue_pie_data'),
    path('payment-success/', payment_success, name='payment_success'),
    path('payment-cancelled/', payment_cancel, name='payment_cancellled'),
    path('create-checkout-session/', create_checkout_session, name='create_checkout_session'),
    path('webhook/', stripe_webhook, name='stripe_webhook'),
    path("residency/submit/", submit_residency_request, name="submit_residency_request"),
    path('api/fees/<uuid:fee_id>/', fee_detail_api, name='fee_detail_api'),
    path('fees/<uuid:fee_id>/delete/', delete_fee, name='delete_fee'),
]

