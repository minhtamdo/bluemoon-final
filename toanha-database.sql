PGDMP      .                }            toanha    17.4    17.4 �    �           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                           false            �           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                           false            �           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                           false            �           1262    25714    toanha    DATABASE     l   CREATE DATABASE toanha WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'en-US';
    DROP DATABASE toanha;
                     postgres    false                        2615    2200    public    SCHEMA        CREATE SCHEMA public;
    DROP SCHEMA public;
                     pg_database_owner    false            �           0    0    SCHEMA public    COMMENT     6   COMMENT ON SCHEMA public IS 'standard public schema';
                        pg_database_owner    false    5            �           1247    25753    change_type    TYPE     x   CREATE TYPE public.change_type AS ENUM (
    'add_member',
    'remove_member',
    'update_info',
    'change_head'
);
    DROP TYPE public.change_type;
       public               postgres    false    5            �           1247    25762    fee_type    TYPE     J   CREATE TYPE public.fee_type AS ENUM (
    'mandatory',
    'voluntary'
);
    DROP TYPE public.fee_type;
       public               postgres    false    5            �           1247    25768    gender    TYPE     M   CREATE TYPE public.gender AS ENUM (
    'Male',
    'Female',
    'Other'
);
    DROP TYPE public.gender;
       public               postgres    false    5            �           1247    25776    notification_type    TYPE     v   CREATE TYPE public.notification_type AS ENUM (
    'fee_reminder',
    'request_status',
    'system_announcement'
);
 $   DROP TYPE public.notification_type;
       public               postgres    false    5            �           1247    25784    payment_method    TYPE     U   CREATE TYPE public.payment_method AS ENUM (
    'qr_code',
    'card',
    'cash'
);
 !   DROP TYPE public.payment_method;
       public               postgres    false    5            �           1247    25792    payment_status    TYPE     H   CREATE TYPE public.payment_status AS ENUM (
    'paid',
    'unpaid'
);
 !   DROP TYPE public.payment_status;
       public               postgres    false    5            �           1247    25798    request_type_enum    TYPE     e   CREATE TYPE public.request_type_enum AS ENUM (
    'temporary_absence',
    'temporary_residence'
);
 $   DROP TYPE public.request_type_enum;
       public               postgres    false    5            �           1247    25804    status    TYPE     D   CREATE TYPE public.status AS ENUM (
    'active',
    'inactive'
);
    DROP TYPE public.status;
       public               postgres    false    5            �           1247    25810    status_account    TYPE     L   CREATE TYPE public.status_account AS ENUM (
    'active',
    'inactive'
);
 !   DROP TYPE public.status_account;
       public               postgres    false    5            �           1247    25816    status_request    TYPE     ]   CREATE TYPE public.status_request AS ENUM (
    'pending',
    'approved',
    'rejected'
);
 !   DROP TYPE public.status_request;
       public               postgres    false    5            �           1247    25824 	   user_role    TYPE     d   CREATE TYPE public.user_role AS ENUM (
    'chu_ho',
    'thu_ky',
    'to_truong',
    'to_pho'
);
    DROP TYPE public.user_role;
       public               postgres    false    5            -           1255    26379     create_payment_for_private_fee()    FUNCTION     <  CREATE FUNCTION public.create_payment_for_private_fee() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Chỉ tạo payment nếu chưa có
    IF NEW.household_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM payments 
        WHERE fee_id = NEW.fee_id AND household_id = NEW.household_id
    ) THEN
        INSERT INTO payments (
            payment_id, fee_id, household_id, paid_at, method, status
        ) VALUES (
            gen_random_uuid(), NEW.fee_id, NEW.household_id, NOW(), 'cash', 'unpaid'
        );
    END IF;

    RETURN NEW;
END;
$$;
 7   DROP FUNCTION public.create_payment_for_private_fee();
       public               postgres    false    5            9           1255    26370    create_payments_for_fee()    FUNCTION     .  CREATE FUNCTION public.create_payments_for_fee() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    hh RECORD;
BEGIN
    -- Chỉ xử lý nếu là phí chung
    IF NEW.is_common THEN
        FOR hh IN SELECT household_id FROM households LOOP
            -- Chỉ tạo nếu chưa tồn tại payment trùng
            IF NOT EXISTS (
                SELECT 1 FROM payments 
                WHERE fee_id = NEW.fee_id AND household_id = hh.household_id
            ) THEN
                INSERT INTO payments (
                    payment_id, fee_id, household_id, paid_at, method, status
                ) VALUES (
                    gen_random_uuid(), NEW.fee_id, hh.household_id, NOW(), 'cash', 'unpaid'
                );
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;
 0   DROP FUNCTION public.create_payments_for_fee();
       public               postgres    false    5            ,           1255    26522 !   delete_private_fee_related_data()    FUNCTION     �  CREATE FUNCTION public.delete_private_fee_related_data() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Chỉ xử lý nếu là phí riêng
    IF NOT OLD.is_common THEN
        -- Xóa các liên kết private fee trong bảng trung gian
        DELETE FROM fee_households WHERE fee_id = OLD.fee_id;

        -- Xóa các payment liên quan đến phí riêng đó
        DELETE FROM payments WHERE fee_id = OLD.fee_id;
    END IF;

    RETURN OLD;
END;
$$;
 8   DROP FUNCTION public.delete_private_fee_related_data();
       public               postgres    false    5            (           1255    25834    hash()    FUNCTION       CREATE FUNCTION public.hash() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
BEGIN
    IF NEW.password_hash IS NOT NULL AND position('$' in NEW.password_hash) = 0 THEN
        NEW.password_hash := crypt(NEW.password_hash, gen_salt('bf'));
    END IF;
    RETURN NEW;
END;
$_$;
    DROP FUNCTION public.hash();
       public               postgres    false    5            *           1255    25835    update_household_size()    FUNCTION     �  CREATE FUNCTION public.update_household_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    count_members INTEGER;
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        SELECT COUNT(*) INTO count_members FROM household_members WHERE household_id = NEW.household_id;
        UPDATE households SET household_size = count_members, updated_at = CURRENT_TIMESTAMP WHERE household_id = NEW.household_id;
    ELSIF TG_OP = 'DELETE' THEN
        SELECT COUNT(*) INTO count_members FROM household_members WHERE household_id = OLD.household_id;
        UPDATE households SET household_size = count_members, updated_at = CURRENT_TIMESTAMP WHERE household_id = OLD.household_id;
    END IF;
    RETURN NULL;
END;
$$;
 .   DROP FUNCTION public.update_household_size();
       public               postgres    false    5            )           1255    26494    update_payments_for_fee()    FUNCTION     �  CREATE FUNCTION public.update_payments_for_fee() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Kiểm tra nếu amount hoặc due_date thay đổi
    IF NEW.amount IS DISTINCT FROM OLD.amount OR NEW.due_date IS DISTINCT FROM OLD.due_date THEN
        -- Cập nhật các payments chưa thanh toán liên quan đến Fee này
        UPDATE payments
        SET paid_at = NOW()
        WHERE fee_id = NEW.fee_id AND status = 'unpaid';
    END IF;

    RETURN NEW;
END;
$$;
 0   DROP FUNCTION public.update_payments_for_fee();
       public               postgres    false    5            +           1255    25836 	   updated()    FUNCTION     �   CREATE FUNCTION public.updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;
     DROP FUNCTION public.updated();
       public               postgres    false    5            �            1259    26042 
   auth_group    TABLE     f   CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);
    DROP TABLE public.auth_group;
       public         heap r       postgres    false    5            �            1259    26041    auth_group_id_seq    SEQUENCE     �   ALTER TABLE public.auth_group ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    239    5            �            1259    26050    auth_group_permissions    TABLE     �   CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);
 *   DROP TABLE public.auth_group_permissions;
       public         heap r       postgres    false    5            �            1259    26049    auth_group_permissions_id_seq    SEQUENCE     �   ALTER TABLE public.auth_group_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    5    241            �            1259    26036    auth_permission    TABLE     �   CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);
 #   DROP TABLE public.auth_permission;
       public         heap r       postgres    false    5            �            1259    26035    auth_permission_id_seq    SEQUENCE     �   ALTER TABLE public.auth_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    5    237            �            1259    26056 	   auth_user    TABLE     �  CREATE TABLE public.auth_user (
    id integer NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL
);
    DROP TABLE public.auth_user;
       public         heap r       postgres    false    5            �            1259    26064    auth_user_groups    TABLE     ~   CREATE TABLE public.auth_user_groups (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL
);
 $   DROP TABLE public.auth_user_groups;
       public         heap r       postgres    false    5            �            1259    26063    auth_user_groups_id_seq    SEQUENCE     �   ALTER TABLE public.auth_user_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    5    245            �            1259    26055    auth_user_id_seq    SEQUENCE     �   ALTER TABLE public.auth_user ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    5    243            �            1259    26070    auth_user_user_permissions    TABLE     �   CREATE TABLE public.auth_user_user_permissions (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    permission_id integer NOT NULL
);
 .   DROP TABLE public.auth_user_user_permissions;
       public         heap r       postgres    false    5            �            1259    26069 !   auth_user_user_permissions_id_seq    SEQUENCE     �   ALTER TABLE public.auth_user_user_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_user_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    247    5            �            1259    26156    core_fee    TABLE       CREATE TABLE public.core_fee (
    fee_id uuid NOT NULL,
    title text NOT NULL,
    description text,
    type character varying(20) NOT NULL,
    amount numeric(12,2) NOT NULL,
    due_date date NOT NULL,
    created_at timestamp with time zone NOT NULL,
    created_by uuid
);
    DROP TABLE public.core_fee;
       public         heap r       postgres    false    5            �            1259    26163    core_household    TABLE     !  CREATE TABLE public.core_household (
    household_id uuid NOT NULL,
    household_number text NOT NULL,
    household_size integer NOT NULL,
    address text NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    head_id uuid
);
 "   DROP TABLE public.core_household;
       public         heap r       postgres    false    5                        1259    26196    core_householdchange    TABLE     {  CREATE TABLE public.core_householdchange (
    change_id uuid NOT NULL,
    change_type character varying(20) NOT NULL,
    description text NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    household_id uuid NOT NULL,
    approved_by_id uuid,
    requested_by_id uuid
);
 (   DROP TABLE public.core_householdchange;
       public         heap r       postgres    false    5            �            1259    26177    core_householdmember    TABLE     �  CREATE TABLE public.core_householdmember (
    member_id uuid NOT NULL,
    full_name text NOT NULL,
    gender character varying(10) NOT NULL,
    other_name text,
    dob date NOT NULL,
    place_of_birth text,
    native_place text,
    ethnic_group text,
    occupation text,
    place_of_work text,
    cccd text,
    issue_date date,
    issued_by text,
    relationship text NOT NULL,
    is_temporary boolean NOT NULL,
    note text,
    joined_at date NOT NULL,
    household_id uuid NOT NULL
);
 (   DROP TABLE public.core_householdmember;
       public         heap r       postgres    false    5            �            1259    26184    core_payment    TABLE       CREATE TABLE public.core_payment (
    payment_id uuid NOT NULL,
    paid_at timestamp with time zone NOT NULL,
    method character varying(20) NOT NULL,
    status character varying(20) NOT NULL,
    fee_id uuid NOT NULL,
    household_id uuid NOT NULL
);
     DROP TABLE public.core_payment;
       public         heap r       postgres    false    5            �            1259    26189    core_residencyrequest    TABLE     �  CREATE TABLE public.core_residencyrequest (
    request_id uuid NOT NULL,
    request_type character varying(30) NOT NULL,
    from_date date NOT NULL,
    to_date date,
    destination text NOT NULL,
    origin text NOT NULL,
    reason text NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    user_id uuid NOT NULL
);
 )   DROP TABLE public.core_residencyrequest;
       public         heap r       postgres    false    5            �            1259    26170 	   core_user    TABLE     N  CREATE TABLE public.core_user (
    user_id uuid NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    role character varying(20) NOT NULL,
    fullname text NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);
    DROP TABLE public.core_user;
       public         heap r       postgres    false    5            �            1259    26128    django_admin_log    TABLE     �  CREATE TABLE public.django_admin_log (
    id integer NOT NULL,
    action_time timestamp with time zone NOT NULL,
    object_id text,
    object_repr character varying(200) NOT NULL,
    action_flag smallint NOT NULL,
    change_message text NOT NULL,
    content_type_id integer,
    user_id integer NOT NULL,
    CONSTRAINT django_admin_log_action_flag_check CHECK ((action_flag >= 0))
);
 $   DROP TABLE public.django_admin_log;
       public         heap r       postgres    false    5            �            1259    26127    django_admin_log_id_seq    SEQUENCE     �   ALTER TABLE public.django_admin_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_admin_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    249    5            �            1259    26028    django_content_type    TABLE     �   CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);
 '   DROP TABLE public.django_content_type;
       public         heap r       postgres    false    5            �            1259    26027    django_content_type_id_seq    SEQUENCE     �   ALTER TABLE public.django_content_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    5    235            �            1259    26020    django_migrations    TABLE     �   CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);
 %   DROP TABLE public.django_migrations;
       public         heap r       postgres    false    5            �            1259    26019    django_migrations_id_seq    SEQUENCE     �   ALTER TABLE public.django_migrations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    233    5                       1259    26340    django_session    TABLE     �   CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);
 "   DROP TABLE public.django_session;
       public         heap r       postgres    false    5                       1259    26350    fee_households    TABLE     y   CREATE TABLE public.fee_households (
    id bigint NOT NULL,
    fee_id uuid NOT NULL,
    household_id uuid NOT NULL
);
 "   DROP TABLE public.fee_households;
       public         heap r       postgres    false    5                       1259    26349    fee_households_id_seq    SEQUENCE     �   ALTER TABLE public.fee_households ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.fee_households_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);
            public               postgres    false    259    5            �            1259    25837    fees    TABLE     ]  CREATE TABLE public.fees (
    fee_id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text,
    type public.fee_type NOT NULL,
    amount numeric(12,2) NOT NULL,
    due_date date NOT NULL,
    created_by uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_common boolean NOT NULL
);
    DROP TABLE public.fees;
       public         heap r       postgres    false    934    5            �            1259    25844    household_changes    TABLE     �  CREATE TABLE public.household_changes (
    change_id uuid DEFAULT gen_random_uuid() NOT NULL,
    household_id uuid NOT NULL,
    change_type public.change_type NOT NULL,
    description text NOT NULL,
    requested_by uuid,
    approved_by uuid,
    status public.status_request DEFAULT 'pending'::public.status_request NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
 %   DROP TABLE public.household_changes;
       public         heap r       postgres    false    958    958    5    931            �            1259    25853    household_members    TABLE     j  CREATE TABLE public.household_members (
    member_id uuid DEFAULT gen_random_uuid() NOT NULL,
    household_id uuid NOT NULL,
    full_name text NOT NULL,
    gender public.gender NOT NULL,
    other_name text,
    dob date NOT NULL,
    place_of_birth text NOT NULL,
    native_place text NOT NULL,
    ethnic_group text NOT NULL,
    occupation text NOT NULL,
    place_of_work text NOT NULL,
    cccd text NOT NULL,
    issue_date date NOT NULL,
    issued_by text NOT NULL,
    relationship text NOT NULL,
    is_temporary boolean DEFAULT false,
    note text,
    joined_at date DEFAULT CURRENT_DATE NOT NULL
);
 %   DROP TABLE public.household_members;
       public         heap r       postgres    false    5    937            �            1259    25861 
   households    TABLE     h  CREATE TABLE public.households (
    household_id uuid DEFAULT gen_random_uuid() NOT NULL,
    household_number text NOT NULL,
    head_id uuid NOT NULL,
    household_size integer NOT NULL,
    address text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
    DROP TABLE public.households;
       public         heap r       postgres    false    5            �            1259    25869    payments    TABLE     @  CREATE TABLE public.payments (
    payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    fee_id uuid,
    household_id uuid,
    paid_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    method public.payment_method NOT NULL,
    status public.payment_status DEFAULT 'paid'::public.payment_status NOT NULL
);
    DROP TABLE public.payments;
       public         heap r       postgres    false    946    946    5    943            �            1259    25875    residency_requests    TABLE     K  CREATE TABLE public.residency_requests (
    request_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    request_type public.request_type_enum NOT NULL,
    from_date date NOT NULL,
    to_date date NOT NULL,
    destination text,
    origin text,
    reason text NOT NULL,
    status public.status_request DEFAULT 'pending'::public.status_request NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_date_range CHECK ((from_date <= to_date))
);
 &   DROP TABLE public.residency_requests;
       public         heap r       postgres    false    958    5    949    958            �            1259    25885    users    TABLE     �  CREATE TABLE public.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    role public.user_role NOT NULL,
    fullname text NOT NULL,
    status public.status_account DEFAULT 'inactive'::public.status_account NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
    DROP TABLE public.users;
       public         heap r       postgres    false    955    5    961    955            �            1259    25894    view_household_changes_history    VIEW     �  CREATE VIEW public.view_household_changes_history AS
 SELECT c.change_id,
    h.household_id,
    h.address,
    c.change_type,
    c.description,
    req.fullname AS requested_by,
    app.fullname AS approved_by,
    c.status,
    c.created_at,
    c.updated_at
   FROM (((public.household_changes c
     JOIN public.households h ON ((c.household_id = h.household_id)))
     LEFT JOIN public.users req ON ((c.requested_by = req.user_id)))
     LEFT JOIN public.users app ON ((c.approved_by = app.user_id)));
 1   DROP VIEW public.view_household_changes_history;
       public       v       postgres    false    219    224    224    221    221    219    219    219    219    219    219    219    219    931    5    958            �            1259    25899    view_household_members    VIEW     \  CREATE VIEW public.view_household_members AS
 SELECT h.household_id,
    h.address,
    m.member_id,
    m.full_name,
    m.other_name,
    m.cccd,
    m.dob,
    m.gender,
    m.relationship,
    m.is_temporary,
    m.note,
    m.joined_at
   FROM (public.households h
     JOIN public.household_members m ON ((h.household_id = m.household_id)));
 )   DROP VIEW public.view_household_members;
       public       v       postgres    false    220    220    220    220    220    220    221    221    220    220    220    220    220    937    5            �            1259    25904 !   view_household_population_summary    VIEW     �  CREATE VIEW public.view_household_population_summary AS
 SELECT h.household_id,
    h.address,
    count(m.member_id) AS num_members,
    sum(
        CASE
            WHEN m.is_temporary THEN 1
            ELSE 0
        END) AS num_temporary_members
   FROM (public.households h
     LEFT JOIN public.household_members m ON ((h.household_id = m.household_id)))
  GROUP BY h.household_id, h.address;
 4   DROP VIEW public.view_household_population_summary;
       public       v       postgres    false    221    221    220    220    220    5            �            1259    25909    view_pending_fees_per_household    VIEW     �  CREATE VIEW public.view_pending_fees_per_household AS
 SELECT h.household_id,
    h.address,
    f.fee_id,
    f.title,
    f.amount,
    f.due_date
   FROM ((public.households h
     CROSS JOIN public.fees f)
     LEFT JOIN public.payments p ON (((f.fee_id = p.fee_id) AND (p.household_id = h.household_id))))
  WHERE ((p.status IS NULL) OR (p.status = 'unpaid'::public.payment_status));
 2   DROP VIEW public.view_pending_fees_per_household;
       public       v       postgres    false    218    946    218    218    218    221    221    222    222    222    5            �            1259    25914    view_pending_household_changes    VIEW     �  CREATE VIEW public.view_pending_household_changes AS
 SELECT c.change_id,
    h.address,
    c.change_type,
    c.description,
    u.fullname AS requested_by,
    c.created_at
   FROM ((public.household_changes c
     JOIN public.households h ON ((c.household_id = h.household_id)))
     LEFT JOIN public.users u ON ((c.requested_by = u.user_id)))
  WHERE (c.status = 'pending'::public.status_request);
 1   DROP VIEW public.view_pending_household_changes;
       public       v       postgres    false    219    219    219    219    221    221    224    224    958    219    219    219    5    931            �            1259    25919    view_pending_residency_requests    VIEW     p  CREATE VIEW public.view_pending_residency_requests AS
 SELECT r.request_id,
    u.fullname AS requester,
    r.request_type,
    r.from_date,
    r.to_date,
    r.destination,
    r.origin,
    r.reason,
    r.created_at
   FROM (public.residency_requests r
     JOIN public.users u ON ((r.user_id = u.user_id)))
  WHERE (r.status = 'pending'::public.status_request);
 2   DROP VIEW public.view_pending_residency_requests;
       public       v       postgres    false    223    223    223    224    224    223    223    223    223    223    958    223    223    5    949            �            1259    25924    view_residency_request_history    VIEW     L  CREATE VIEW public.view_residency_request_history AS
 SELECT r.request_id,
    u.fullname,
    r.request_type,
    r.from_date,
    r.to_date,
    r.destination,
    r.origin,
    r.reason,
    r.status,
    r.created_at,
    r.updated_at
   FROM (public.residency_requests r
     JOIN public.users u ON ((r.user_id = u.user_id)));
 1   DROP VIEW public.view_residency_request_history;
       public       v       postgres    false    223    223    223    223    223    223    223    223    223    223    223    224    224    958    5    949            x          0    26042 
   auth_group 
   TABLE DATA           .   COPY public.auth_group (id, name) FROM stdin;
    public               postgres    false    239   D      z          0    26050    auth_group_permissions 
   TABLE DATA           M   COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
    public               postgres    false    241   8D      v          0    26036    auth_permission 
   TABLE DATA           N   COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
    public               postgres    false    237   UD      |          0    26056 	   auth_user 
   TABLE DATA           �   COPY public.auth_user (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined) FROM stdin;
    public               postgres    false    243   uF      ~          0    26064    auth_user_groups 
   TABLE DATA           A   COPY public.auth_user_groups (id, user_id, group_id) FROM stdin;
    public               postgres    false    245   :G      �          0    26070    auth_user_user_permissions 
   TABLE DATA           P   COPY public.auth_user_user_permissions (id, user_id, permission_id) FROM stdin;
    public               postgres    false    247   WG      �          0    26156    core_fee 
   TABLE DATA           n   COPY public.core_fee (fee_id, title, description, type, amount, due_date, created_at, created_by) FROM stdin;
    public               postgres    false    250   tG      �          0    26163    core_household 
   TABLE DATA           �   COPY public.core_household (household_id, household_number, household_size, address, created_at, updated_at, head_id) FROM stdin;
    public               postgres    false    251   �G      �          0    26196    core_householdchange 
   TABLE DATA           �   COPY public.core_householdchange (change_id, change_type, description, status, created_at, updated_at, household_id, approved_by_id, requested_by_id) FROM stdin;
    public               postgres    false    256   �G      �          0    26177    core_householdmember 
   TABLE DATA           �   COPY public.core_householdmember (member_id, full_name, gender, other_name, dob, place_of_birth, native_place, ethnic_group, occupation, place_of_work, cccd, issue_date, issued_by, relationship, is_temporary, note, joined_at, household_id) FROM stdin;
    public               postgres    false    253   �G      �          0    26184    core_payment 
   TABLE DATA           a   COPY public.core_payment (payment_id, paid_at, method, status, fee_id, household_id) FROM stdin;
    public               postgres    false    254   �G      �          0    26189    core_residencyrequest 
   TABLE DATA           �   COPY public.core_residencyrequest (request_id, request_type, from_date, to_date, destination, origin, reason, status, created_at, updated_at, user_id) FROM stdin;
    public               postgres    false    255   H      �          0    26170 	   core_user 
   TABLE DATA           u   COPY public.core_user (user_id, username, password_hash, role, fullname, status, created_at, updated_at) FROM stdin;
    public               postgres    false    252   "H      �          0    26128    django_admin_log 
   TABLE DATA           �   COPY public.django_admin_log (id, action_time, object_id, object_repr, action_flag, change_message, content_type_id, user_id) FROM stdin;
    public               postgres    false    249   ?H      t          0    26028    django_content_type 
   TABLE DATA           C   COPY public.django_content_type (id, app_label, model) FROM stdin;
    public               postgres    false    235   =I      r          0    26020    django_migrations 
   TABLE DATA           C   COPY public.django_migrations (id, app, name, applied) FROM stdin;
    public               postgres    false    233   �I      �          0    26340    django_session 
   TABLE DATA           P   COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
    public               postgres    false    257   L      �          0    26350    fee_households 
   TABLE DATA           B   COPY public.fee_households (id, fee_id, household_id) FROM stdin;
    public               postgres    false    259   6R      j          0    25837    fees 
   TABLE DATA           u   COPY public.fees (fee_id, title, description, type, amount, due_date, created_by, created_at, is_common) FROM stdin;
    public               postgres    false    218   0S      k          0    25844    household_changes 
   TABLE DATA           �   COPY public.household_changes (change_id, household_id, change_type, description, requested_by, approved_by, status, created_at, updated_at) FROM stdin;
    public               postgres    false    219   �U      l          0    25853    household_members 
   TABLE DATA           �   COPY public.household_members (member_id, household_id, full_name, gender, other_name, dob, place_of_birth, native_place, ethnic_group, occupation, place_of_work, cccd, issue_date, issued_by, relationship, is_temporary, note, joined_at) FROM stdin;
    public               postgres    false    220   �U      m          0    25861 
   households 
   TABLE DATA           ~   COPY public.households (household_id, household_number, head_id, household_size, address, created_at, updated_at) FROM stdin;
    public               postgres    false    221   -Z      n          0    25869    payments 
   TABLE DATA           ]   COPY public.payments (payment_id, fee_id, household_id, paid_at, method, status) FROM stdin;
    public               postgres    false    222   �[      o          0    25875    residency_requests 
   TABLE DATA           �   COPY public.residency_requests (request_id, user_id, request_type, from_date, to_date, destination, origin, reason, status, created_at, updated_at) FROM stdin;
    public               postgres    false    223   x`      p          0    25885    users 
   TABLE DATA           q   COPY public.users (user_id, username, password_hash, role, fullname, status, created_at, updated_at) FROM stdin;
    public               postgres    false    224   �a      �           0    0    auth_group_id_seq    SEQUENCE SET     @   SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);
          public               postgres    false    238            �           0    0    auth_group_permissions_id_seq    SEQUENCE SET     L   SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);
          public               postgres    false    240            �           0    0    auth_permission_id_seq    SEQUENCE SET     E   SELECT pg_catalog.setval('public.auth_permission_id_seq', 52, true);
          public               postgres    false    236            �           0    0    auth_user_groups_id_seq    SEQUENCE SET     F   SELECT pg_catalog.setval('public.auth_user_groups_id_seq', 1, false);
          public               postgres    false    244            �           0    0    auth_user_id_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.auth_user_id_seq', 1, true);
          public               postgres    false    242            �           0    0 !   auth_user_user_permissions_id_seq    SEQUENCE SET     P   SELECT pg_catalog.setval('public.auth_user_user_permissions_id_seq', 1, false);
          public               postgres    false    246            �           0    0    django_admin_log_id_seq    SEQUENCE SET     E   SELECT pg_catalog.setval('public.django_admin_log_id_seq', 3, true);
          public               postgres    false    248            �           0    0    django_content_type_id_seq    SEQUENCE SET     I   SELECT pg_catalog.setval('public.django_content_type_id_seq', 13, true);
          public               postgres    false    234            �           0    0    django_migrations_id_seq    SEQUENCE SET     G   SELECT pg_catalog.setval('public.django_migrations_id_seq', 23, true);
          public               postgres    false    232            �           0    0    fee_households_id_seq    SEQUENCE SET     D   SELECT pg_catalog.setval('public.fee_households_id_seq', 24, true);
          public               postgres    false    258            k           2606    26154    auth_group auth_group_name_key 
   CONSTRAINT     Y   ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);
 H   ALTER TABLE ONLY public.auth_group DROP CONSTRAINT auth_group_name_key;
       public                 postgres    false    239            p           2606    26085 R   auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);
 |   ALTER TABLE ONLY public.auth_group_permissions DROP CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq;
       public                 postgres    false    241    241            s           2606    26054 2   auth_group_permissions auth_group_permissions_pkey 
   CONSTRAINT     p   ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);
 \   ALTER TABLE ONLY public.auth_group_permissions DROP CONSTRAINT auth_group_permissions_pkey;
       public                 postgres    false    241            m           2606    26046    auth_group auth_group_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);
 D   ALTER TABLE ONLY public.auth_group DROP CONSTRAINT auth_group_pkey;
       public                 postgres    false    239            f           2606    26076 F   auth_permission auth_permission_content_type_id_codename_01ab375a_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);
 p   ALTER TABLE ONLY public.auth_permission DROP CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq;
       public                 postgres    false    237    237            h           2606    26040 $   auth_permission auth_permission_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);
 N   ALTER TABLE ONLY public.auth_permission DROP CONSTRAINT auth_permission_pkey;
       public                 postgres    false    237            {           2606    26068 &   auth_user_groups auth_user_groups_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_pkey PRIMARY KEY (id);
 P   ALTER TABLE ONLY public.auth_user_groups DROP CONSTRAINT auth_user_groups_pkey;
       public                 postgres    false    245            ~           2606    26100 @   auth_user_groups auth_user_groups_user_id_group_id_94350c0c_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq UNIQUE (user_id, group_id);
 j   ALTER TABLE ONLY public.auth_user_groups DROP CONSTRAINT auth_user_groups_user_id_group_id_94350c0c_uniq;
       public                 postgres    false    245    245            u           2606    26060    auth_user auth_user_pkey 
   CONSTRAINT     V   ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_pkey PRIMARY KEY (id);
 B   ALTER TABLE ONLY public.auth_user DROP CONSTRAINT auth_user_pkey;
       public                 postgres    false    243            �           2606    26074 :   auth_user_user_permissions auth_user_user_permissions_pkey 
   CONSTRAINT     x   ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_pkey PRIMARY KEY (id);
 d   ALTER TABLE ONLY public.auth_user_user_permissions DROP CONSTRAINT auth_user_user_permissions_pkey;
       public                 postgres    false    247            �           2606    26114 Y   auth_user_user_permissions auth_user_user_permissions_user_id_permission_id_14a6b632_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq UNIQUE (user_id, permission_id);
 �   ALTER TABLE ONLY public.auth_user_user_permissions DROP CONSTRAINT auth_user_user_permissions_user_id_permission_id_14a6b632_uniq;
       public                 postgres    false    247    247            x           2606    26149     auth_user auth_user_username_key 
   CONSTRAINT     _   ALTER TABLE ONLY public.auth_user
    ADD CONSTRAINT auth_user_username_key UNIQUE (username);
 J   ALTER TABLE ONLY public.auth_user DROP CONSTRAINT auth_user_username_key;
       public                 postgres    false    243            �           2606    26162    core_fee core_fee_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.core_fee
    ADD CONSTRAINT core_fee_pkey PRIMARY KEY (fee_id);
 @   ALTER TABLE ONLY public.core_fee DROP CONSTRAINT core_fee_pkey;
       public                 postgres    false    250            �           2606    26169 "   core_household core_household_pkey 
   CONSTRAINT     j   ALTER TABLE ONLY public.core_household
    ADD CONSTRAINT core_household_pkey PRIMARY KEY (household_id);
 L   ALTER TABLE ONLY public.core_household DROP CONSTRAINT core_household_pkey;
       public                 postgres    false    251            �           2606    26202 .   core_householdchange core_householdchange_pkey 
   CONSTRAINT     s   ALTER TABLE ONLY public.core_householdchange
    ADD CONSTRAINT core_householdchange_pkey PRIMARY KEY (change_id);
 X   ALTER TABLE ONLY public.core_householdchange DROP CONSTRAINT core_householdchange_pkey;
       public                 postgres    false    256            �           2606    26183 .   core_householdmember core_householdmember_pkey 
   CONSTRAINT     s   ALTER TABLE ONLY public.core_householdmember
    ADD CONSTRAINT core_householdmember_pkey PRIMARY KEY (member_id);
 X   ALTER TABLE ONLY public.core_householdmember DROP CONSTRAINT core_householdmember_pkey;
       public                 postgres    false    253            �           2606    26188    core_payment core_payment_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.core_payment
    ADD CONSTRAINT core_payment_pkey PRIMARY KEY (payment_id);
 H   ALTER TABLE ONLY public.core_payment DROP CONSTRAINT core_payment_pkey;
       public                 postgres    false    254            �           2606    26195 0   core_residencyrequest core_residencyrequest_pkey 
   CONSTRAINT     v   ALTER TABLE ONLY public.core_residencyrequest
    ADD CONSTRAINT core_residencyrequest_pkey PRIMARY KEY (request_id);
 Z   ALTER TABLE ONLY public.core_residencyrequest DROP CONSTRAINT core_residencyrequest_pkey;
       public                 postgres    false    255            �           2606    26176    core_user core_user_pkey 
   CONSTRAINT     [   ALTER TABLE ONLY public.core_user
    ADD CONSTRAINT core_user_pkey PRIMARY KEY (user_id);
 B   ALTER TABLE ONLY public.core_user DROP CONSTRAINT core_user_pkey;
       public                 postgres    false    252            �           2606    26135 &   django_admin_log django_admin_log_pkey 
   CONSTRAINT     d   ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_pkey PRIMARY KEY (id);
 P   ALTER TABLE ONLY public.django_admin_log DROP CONSTRAINT django_admin_log_pkey;
       public                 postgres    false    249            a           2606    26034 E   django_content_type django_content_type_app_label_model_76bd3d3b_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);
 o   ALTER TABLE ONLY public.django_content_type DROP CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq;
       public                 postgres    false    235    235            c           2606    26032 ,   django_content_type django_content_type_pkey 
   CONSTRAINT     j   ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);
 V   ALTER TABLE ONLY public.django_content_type DROP CONSTRAINT django_content_type_pkey;
       public                 postgres    false    235            _           2606    26026 (   django_migrations django_migrations_pkey 
   CONSTRAINT     f   ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);
 R   ALTER TABLE ONLY public.django_migrations DROP CONSTRAINT django_migrations_pkey;
       public                 postgres    false    233            �           2606    26346 "   django_session django_session_pkey 
   CONSTRAINT     i   ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);
 L   ALTER TABLE ONLY public.django_session DROP CONSTRAINT django_session_pkey;
       public                 postgres    false    257            �           2606    26357 ?   fee_households fee_households_fee_id_household_id_7fb4348a_uniq 
   CONSTRAINT     �   ALTER TABLE ONLY public.fee_households
    ADD CONSTRAINT fee_households_fee_id_household_id_7fb4348a_uniq UNIQUE (fee_id, household_id);
 i   ALTER TABLE ONLY public.fee_households DROP CONSTRAINT fee_households_fee_id_household_id_7fb4348a_uniq;
       public                 postgres    false    259    259            �           2606    26354 "   fee_households fee_households_pkey 
   CONSTRAINT     `   ALTER TABLE ONLY public.fee_households
    ADD CONSTRAINT fee_households_pkey PRIMARY KEY (id);
 L   ALTER TABLE ONLY public.fee_households DROP CONSTRAINT fee_households_pkey;
       public                 postgres    false    259            C           2606    25929    fees fees_pkey 
   CONSTRAINT     P   ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fees_pkey PRIMARY KEY (fee_id);
 8   ALTER TABLE ONLY public.fees DROP CONSTRAINT fees_pkey;
       public                 postgres    false    218            F           2606    25931 (   household_changes household_changes_pkey 
   CONSTRAINT     m   ALTER TABLE ONLY public.household_changes
    ADD CONSTRAINT household_changes_pkey PRIMARY KEY (change_id);
 R   ALTER TABLE ONLY public.household_changes DROP CONSTRAINT household_changes_pkey;
       public                 postgres    false    219            I           2606    25933 ,   household_members household_members_cccd_key 
   CONSTRAINT     g   ALTER TABLE ONLY public.household_members
    ADD CONSTRAINT household_members_cccd_key UNIQUE (cccd);
 V   ALTER TABLE ONLY public.household_members DROP CONSTRAINT household_members_cccd_key;
       public                 postgres    false    220            K           2606    25935 (   household_members household_members_pkey 
   CONSTRAINT     m   ALTER TABLE ONLY public.household_members
    ADD CONSTRAINT household_members_pkey PRIMARY KEY (member_id);
 R   ALTER TABLE ONLY public.household_members DROP CONSTRAINT household_members_pkey;
       public                 postgres    false    220            N           2606    25937 *   households households_household_number_key 
   CONSTRAINT     q   ALTER TABLE ONLY public.households
    ADD CONSTRAINT households_household_number_key UNIQUE (household_number);
 T   ALTER TABLE ONLY public.households DROP CONSTRAINT households_household_number_key;
       public                 postgres    false    221            P           2606    25939    households households_pkey 
   CONSTRAINT     b   ALTER TABLE ONLY public.households
    ADD CONSTRAINT households_pkey PRIMARY KEY (household_id);
 D   ALTER TABLE ONLY public.households DROP CONSTRAINT households_pkey;
       public                 postgres    false    221            U           2606    25941    payments payments_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (payment_id);
 @   ALTER TABLE ONLY public.payments DROP CONSTRAINT payments_pkey;
       public                 postgres    false    222            Y           2606    25943 *   residency_requests residency_requests_pkey 
   CONSTRAINT     p   ALTER TABLE ONLY public.residency_requests
    ADD CONSTRAINT residency_requests_pkey PRIMARY KEY (request_id);
 T   ALTER TABLE ONLY public.residency_requests DROP CONSTRAINT residency_requests_pkey;
       public                 postgres    false    223            [           2606    25945    users users_pkey 
   CONSTRAINT     S   ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);
 :   ALTER TABLE ONLY public.users DROP CONSTRAINT users_pkey;
       public                 postgres    false    224            ]           2606    25947    users users_username_key 
   CONSTRAINT     W   ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);
 B   ALTER TABLE ONLY public.users DROP CONSTRAINT users_username_key;
       public                 postgres    false    224            i           1259    26155    auth_group_name_a6ea08ec_like    INDEX     h   CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);
 1   DROP INDEX public.auth_group_name_a6ea08ec_like;
       public                 postgres    false    239            n           1259    26096 (   auth_group_permissions_group_id_b120cbf9    INDEX     o   CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);
 <   DROP INDEX public.auth_group_permissions_group_id_b120cbf9;
       public                 postgres    false    241            q           1259    26097 -   auth_group_permissions_permission_id_84c5c92e    INDEX     y   CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);
 A   DROP INDEX public.auth_group_permissions_permission_id_84c5c92e;
       public                 postgres    false    241            d           1259    26082 (   auth_permission_content_type_id_2f476e4b    INDEX     o   CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);
 <   DROP INDEX public.auth_permission_content_type_id_2f476e4b;
       public                 postgres    false    237            y           1259    26112 "   auth_user_groups_group_id_97559544    INDEX     c   CREATE INDEX auth_user_groups_group_id_97559544 ON public.auth_user_groups USING btree (group_id);
 6   DROP INDEX public.auth_user_groups_group_id_97559544;
       public                 postgres    false    245            |           1259    26111 !   auth_user_groups_user_id_6a12ed8b    INDEX     a   CREATE INDEX auth_user_groups_user_id_6a12ed8b ON public.auth_user_groups USING btree (user_id);
 5   DROP INDEX public.auth_user_groups_user_id_6a12ed8b;
       public                 postgres    false    245                       1259    26126 1   auth_user_user_permissions_permission_id_1fbb5f2c    INDEX     �   CREATE INDEX auth_user_user_permissions_permission_id_1fbb5f2c ON public.auth_user_user_permissions USING btree (permission_id);
 E   DROP INDEX public.auth_user_user_permissions_permission_id_1fbb5f2c;
       public                 postgres    false    247            �           1259    26125 +   auth_user_user_permissions_user_id_a95ead1b    INDEX     u   CREATE INDEX auth_user_user_permissions_user_id_a95ead1b ON public.auth_user_user_permissions USING btree (user_id);
 ?   DROP INDEX public.auth_user_user_permissions_user_id_a95ead1b;
       public                 postgres    false    247            v           1259    26150     auth_user_username_6821ab7c_like    INDEX     n   CREATE INDEX auth_user_username_6821ab7c_like ON public.auth_user USING btree (username varchar_pattern_ops);
 4   DROP INDEX public.auth_user_username_6821ab7c_like;
       public                 postgres    false    243            �           1259    26256    core_fee_created_by_id_2c30bb6a    INDEX     Z   CREATE INDEX core_fee_created_by_id_2c30bb6a ON public.core_fee USING btree (created_by);
 3   DROP INDEX public.core_fee_created_by_id_2c30bb6a;
       public                 postgres    false    250            �           1259    26255    core_household_head_id_7a2b2669    INDEX     ]   CREATE INDEX core_household_head_id_7a2b2669 ON public.core_household USING btree (head_id);
 3   DROP INDEX public.core_household_head_id_7a2b2669;
       public                 postgres    false    251            �           1259    26253 ,   core_householdchange_approved_by_id_601161a4    INDEX     w   CREATE INDEX core_householdchange_approved_by_id_601161a4 ON public.core_householdchange USING btree (approved_by_id);
 @   DROP INDEX public.core_householdchange_approved_by_id_601161a4;
       public                 postgres    false    256            �           1259    26252 *   core_householdchange_household_id_b63e2ddd    INDEX     s   CREATE INDEX core_householdchange_household_id_b63e2ddd ON public.core_householdchange USING btree (household_id);
 >   DROP INDEX public.core_householdchange_household_id_b63e2ddd;
       public                 postgres    false    256            �           1259    26254 -   core_householdchange_requested_by_id_713e5619    INDEX     y   CREATE INDEX core_householdchange_requested_by_id_713e5619 ON public.core_householdchange USING btree (requested_by_id);
 A   DROP INDEX public.core_householdchange_requested_by_id_713e5619;
       public                 postgres    false    256            �           1259    26218 *   core_householdmember_household_id_ad7db2c8    INDEX     s   CREATE INDEX core_householdmember_household_id_ad7db2c8 ON public.core_householdmember USING btree (household_id);
 >   DROP INDEX public.core_householdmember_household_id_ad7db2c8;
       public                 postgres    false    253            �           1259    26229    core_payment_fee_id_4934488e    INDEX     W   CREATE INDEX core_payment_fee_id_4934488e ON public.core_payment USING btree (fee_id);
 0   DROP INDEX public.core_payment_fee_id_4934488e;
       public                 postgres    false    254            �           1259    26230 "   core_payment_household_id_aedeface    INDEX     c   CREATE INDEX core_payment_household_id_aedeface ON public.core_payment USING btree (household_id);
 6   DROP INDEX public.core_payment_household_id_aedeface;
       public                 postgres    false    254            �           1259    26236 &   core_residencyrequest_user_id_91090bdf    INDEX     k   CREATE INDEX core_residencyrequest_user_id_91090bdf ON public.core_residencyrequest USING btree (user_id);
 :   DROP INDEX public.core_residencyrequest_user_id_91090bdf;
       public                 postgres    false    255            �           1259    26146 )   django_admin_log_content_type_id_c4bce8eb    INDEX     q   CREATE INDEX django_admin_log_content_type_id_c4bce8eb ON public.django_admin_log USING btree (content_type_id);
 =   DROP INDEX public.django_admin_log_content_type_id_c4bce8eb;
       public                 postgres    false    249            �           1259    26147 !   django_admin_log_user_id_c564eba6    INDEX     a   CREATE INDEX django_admin_log_user_id_c564eba6 ON public.django_admin_log USING btree (user_id);
 5   DROP INDEX public.django_admin_log_user_id_c564eba6;
       public                 postgres    false    249            �           1259    26348 #   django_session_expire_date_a5c62663    INDEX     e   CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);
 7   DROP INDEX public.django_session_expire_date_a5c62663;
       public                 postgres    false    257            �           1259    26347 (   django_session_session_key_c0390e0f_like    INDEX     ~   CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);
 <   DROP INDEX public.django_session_session_key_c0390e0f_like;
       public                 postgres    false    257            �           1259    26368    fee_households_fee_id_ec6f5463    INDEX     [   CREATE INDEX fee_households_fee_id_ec6f5463 ON public.fee_households USING btree (fee_id);
 2   DROP INDEX public.fee_households_fee_id_ec6f5463;
       public                 postgres    false    259            �           1259    26369 $   fee_households_household_id_6466fcbf    INDEX     g   CREATE INDEX fee_households_household_id_6466fcbf ON public.fee_households USING btree (household_id);
 8   DROP INDEX public.fee_households_household_id_6466fcbf;
       public                 postgres    false    259            D           1259    25948    idx_fees_due_date    INDEX     F   CREATE INDEX idx_fees_due_date ON public.fees USING btree (due_date);
 %   DROP INDEX public.idx_fees_due_date;
       public                 postgres    false    218            G           1259    25949 !   idx_household_changes_status_type    INDEX     n   CREATE INDEX idx_household_changes_status_type ON public.household_changes USING btree (status, change_type);
 5   DROP INDEX public.idx_household_changes_status_type;
       public                 postgres    false    219    219            L           1259    25950 "   idx_household_members_household_id    INDEX     h   CREATE INDEX idx_household_members_household_id ON public.household_members USING btree (household_id);
 6   DROP INDEX public.idx_household_members_household_id;
       public                 postgres    false    220            Q           1259    25951    idx_payments_fee_id    INDEX     J   CREATE INDEX idx_payments_fee_id ON public.payments USING btree (fee_id);
 '   DROP INDEX public.idx_payments_fee_id;
       public                 postgres    false    222            R           1259    25952    idx_payments_household_id    INDEX     V   CREATE INDEX idx_payments_household_id ON public.payments USING btree (household_id);
 -   DROP INDEX public.idx_payments_household_id;
       public                 postgres    false    222            S           1259    25953    idx_payments_status_method    INDEX     Y   CREATE INDEX idx_payments_status_method ON public.payments USING btree (status, method);
 .   DROP INDEX public.idx_payments_status_method;
       public                 postgres    false    222    222            V           1259    25954    idx_residency_requests_status    INDEX     ^   CREATE INDEX idx_residency_requests_status ON public.residency_requests USING btree (status);
 1   DROP INDEX public.idx_residency_requests_status;
       public                 postgres    false    223            W           1259    25955    idx_residency_requests_user_id    INDEX     `   CREATE INDEX idx_residency_requests_user_id ON public.residency_requests USING btree (user_id);
 2   DROP INDEX public.idx_residency_requests_user_id;
       public                 postgres    false    223            �           2620    26380 -   fee_households trg_create_payment_private_fee    TRIGGER     �   CREATE TRIGGER trg_create_payment_private_fee AFTER INSERT ON public.fee_households FOR EACH ROW EXECUTE FUNCTION public.create_payment_for_private_fee();
 F   DROP TRIGGER trg_create_payment_private_fee ON public.fee_households;
       public               postgres    false    259    301            �           2620    26378    fees trg_create_payments    TRIGGER        CREATE TRIGGER trg_create_payments AFTER INSERT ON public.fees FOR EACH ROW EXECUTE FUNCTION public.create_payments_for_fee();
 1   DROP TRIGGER trg_create_payments ON public.fees;
       public               postgres    false    218    313            �           2620    26371 )   fees trg_create_payments_after_fee_insert    TRIGGER     �   CREATE TRIGGER trg_create_payments_after_fee_insert AFTER INSERT ON public.fees FOR EACH ROW EXECUTE FUNCTION public.create_payments_for_fee();
 B   DROP TRIGGER trg_create_payments_after_fee_insert ON public.fees;
       public               postgres    false    313    218            �           2620    26523 (   fees trg_delete_private_fee_related_data    TRIGGER     �   CREATE TRIGGER trg_delete_private_fee_related_data BEFORE DELETE ON public.fees FOR EACH ROW EXECUTE FUNCTION public.delete_private_fee_related_data();
 A   DROP TRIGGER trg_delete_private_fee_related_data ON public.fees;
       public               postgres    false    300    218            �           2620    26496     fees trg_update_payments_for_fee    TRIGGER     �   CREATE TRIGGER trg_update_payments_for_fee AFTER UPDATE ON public.fees FOR EACH ROW EXECUTE FUNCTION public.update_payments_for_fee();
 9   DROP TRIGGER trg_update_payments_for_fee ON public.fees;
       public               postgres    false    297    218            �           2620    25957    users trigger_hash    TRIGGER     q   CREATE TRIGGER trigger_hash BEFORE INSERT OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.hash();
 +   DROP TRIGGER trigger_hash ON public.users;
       public               postgres    false    224    296            �           2620    25958 2   household_changes trigger_update_household_changes    TRIGGER     �   CREATE TRIGGER trigger_update_household_changes BEFORE UPDATE ON public.household_changes FOR EACH ROW EXECUTE FUNCTION public.updated();
 K   DROP TRIGGER trigger_update_household_changes ON public.household_changes;
       public               postgres    false    299    219            �           2620    25959 /   household_members trigger_update_household_size    TRIGGER     �   CREATE TRIGGER trigger_update_household_size AFTER INSERT OR DELETE OR UPDATE ON public.household_members FOR EACH ROW EXECUTE FUNCTION public.update_household_size();
 H   DROP TRIGGER trigger_update_household_size ON public.household_members;
       public               postgres    false    220    298            �           2620    25960 $   households trigger_update_households    TRIGGER     |   CREATE TRIGGER trigger_update_households BEFORE UPDATE ON public.households FOR EACH ROW EXECUTE FUNCTION public.updated();
 =   DROP TRIGGER trigger_update_households ON public.households;
       public               postgres    false    221    299            �           2620    25961 4   residency_requests trigger_update_residency_requests    TRIGGER     �   CREATE TRIGGER trigger_update_residency_requests BEFORE UPDATE ON public.residency_requests FOR EACH ROW EXECUTE FUNCTION public.updated();
 M   DROP TRIGGER trigger_update_residency_requests ON public.residency_requests;
       public               postgres    false    223    299            �           2620    25962    users trigger_update_user    TRIGGER     q   CREATE TRIGGER trigger_update_user BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION public.updated();
 2   DROP TRIGGER trigger_update_user ON public.users;
       public               postgres    false    299    224            �           2606    26091 O   auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;
 y   ALTER TABLE ONLY public.auth_group_permissions DROP CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm;
       public               postgres    false    241    4968    237            �           2606    26086 P   auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;
 z   ALTER TABLE ONLY public.auth_group_permissions DROP CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id;
       public               postgres    false    4973    239    241            �           2606    26077 E   auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;
 o   ALTER TABLE ONLY public.auth_permission DROP CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co;
       public               postgres    false    235    4963    237            �           2606    26106 D   auth_user_groups auth_user_groups_group_id_97559544_fk_auth_group_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;
 n   ALTER TABLE ONLY public.auth_user_groups DROP CONSTRAINT auth_user_groups_group_id_97559544_fk_auth_group_id;
       public               postgres    false    245    4973    239            �           2606    26101 B   auth_user_groups auth_user_groups_user_id_6a12ed8b_fk_auth_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_groups
    ADD CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;
 l   ALTER TABLE ONLY public.auth_user_groups DROP CONSTRAINT auth_user_groups_user_id_6a12ed8b_fk_auth_user_id;
       public               postgres    false    4981    245    243            �           2606    26120 S   auth_user_user_permissions auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;
 }   ALTER TABLE ONLY public.auth_user_user_permissions DROP CONSTRAINT auth_user_user_permi_permission_id_1fbb5f2c_fk_auth_perm;
       public               postgres    false    247    4968    237            �           2606    26115 V   auth_user_user_permissions auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.auth_user_user_permissions
    ADD CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;
 �   ALTER TABLE ONLY public.auth_user_user_permissions DROP CONSTRAINT auth_user_user_permissions_user_id_a95ead1b_fk_auth_user_id;
       public               postgres    false    247    243    4981            �           2606    26208 =   core_fee core_fee_created_by_id_2c30bb6a_fk_core_user_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_fee
    ADD CONSTRAINT core_fee_created_by_id_2c30bb6a_fk_core_user_user_id FOREIGN KEY (created_by) REFERENCES public.core_user(user_id) DEFERRABLE INITIALLY DEFERRED;
 g   ALTER TABLE ONLY public.core_fee DROP CONSTRAINT core_fee_created_by_id_2c30bb6a_fk_core_user_user_id;
       public               postgres    false    5008    250    252            �           2606    26203 C   core_household core_household_head_id_7a2b2669_fk_core_user_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_household
    ADD CONSTRAINT core_household_head_id_7a2b2669_fk_core_user_user_id FOREIGN KEY (head_id) REFERENCES public.core_user(user_id) DEFERRABLE INITIALLY DEFERRED;
 m   ALTER TABLE ONLY public.core_household DROP CONSTRAINT core_household_head_id_7a2b2669_fk_core_user_user_id;
       public               postgres    false    251    252    5008            �           2606    26242 N   core_householdchange core_householdchange_approved_by_id_601161a4_fk_core_user    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_householdchange
    ADD CONSTRAINT core_householdchange_approved_by_id_601161a4_fk_core_user FOREIGN KEY (approved_by_id) REFERENCES public.core_user(user_id) DEFERRABLE INITIALLY DEFERRED;
 x   ALTER TABLE ONLY public.core_householdchange DROP CONSTRAINT core_householdchange_approved_by_id_601161a4_fk_core_user;
       public               postgres    false    5008    252    256            �           2606    26237 L   core_householdchange core_householdchange_household_id_b63e2ddd_fk_core_hous    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_householdchange
    ADD CONSTRAINT core_householdchange_household_id_b63e2ddd_fk_core_hous FOREIGN KEY (household_id) REFERENCES public.core_household(household_id) DEFERRABLE INITIALLY DEFERRED;
 v   ALTER TABLE ONLY public.core_householdchange DROP CONSTRAINT core_householdchange_household_id_b63e2ddd_fk_core_hous;
       public               postgres    false    5006    251    256            �           2606    26247 O   core_householdchange core_householdchange_requested_by_id_713e5619_fk_core_user    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_householdchange
    ADD CONSTRAINT core_householdchange_requested_by_id_713e5619_fk_core_user FOREIGN KEY (requested_by_id) REFERENCES public.core_user(user_id) DEFERRABLE INITIALLY DEFERRED;
 y   ALTER TABLE ONLY public.core_householdchange DROP CONSTRAINT core_householdchange_requested_by_id_713e5619_fk_core_user;
       public               postgres    false    5008    256    252            �           2606    26213 L   core_householdmember core_householdmember_household_id_ad7db2c8_fk_core_hous    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_householdmember
    ADD CONSTRAINT core_householdmember_household_id_ad7db2c8_fk_core_hous FOREIGN KEY (household_id) REFERENCES public.core_household(household_id) DEFERRABLE INITIALLY DEFERRED;
 v   ALTER TABLE ONLY public.core_householdmember DROP CONSTRAINT core_householdmember_household_id_ad7db2c8_fk_core_hous;
       public               postgres    false    5006    253    251            �           2606    26219 <   core_payment core_payment_fee_id_4934488e_fk_core_fee_fee_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_payment
    ADD CONSTRAINT core_payment_fee_id_4934488e_fk_core_fee_fee_id FOREIGN KEY (fee_id) REFERENCES public.core_fee(fee_id) DEFERRABLE INITIALLY DEFERRED;
 f   ALTER TABLE ONLY public.core_payment DROP CONSTRAINT core_payment_fee_id_4934488e_fk_core_fee_fee_id;
       public               postgres    false    5003    254    250            �           2606    26224 <   core_payment core_payment_household_id_aedeface_fk_core_hous    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_payment
    ADD CONSTRAINT core_payment_household_id_aedeface_fk_core_hous FOREIGN KEY (household_id) REFERENCES public.core_household(household_id) DEFERRABLE INITIALLY DEFERRED;
 f   ALTER TABLE ONLY public.core_payment DROP CONSTRAINT core_payment_household_id_aedeface_fk_core_hous;
       public               postgres    false    254    5006    251            �           2606    26231 Q   core_residencyrequest core_residencyrequest_user_id_91090bdf_fk_core_user_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.core_residencyrequest
    ADD CONSTRAINT core_residencyrequest_user_id_91090bdf_fk_core_user_user_id FOREIGN KEY (user_id) REFERENCES public.core_user(user_id) DEFERRABLE INITIALLY DEFERRED;
 {   ALTER TABLE ONLY public.core_residencyrequest DROP CONSTRAINT core_residencyrequest_user_id_91090bdf_fk_core_user_user_id;
       public               postgres    false    255    252    5008            �           2606    26136 G   django_admin_log django_admin_log_content_type_id_c4bce8eb_fk_django_co    FK CONSTRAINT     �   ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;
 q   ALTER TABLE ONLY public.django_admin_log DROP CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co;
       public               postgres    false    4963    235    249            �           2606    26141 B   django_admin_log django_admin_log_user_id_c564eba6_fk_auth_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_user_id_c564eba6_fk_auth_user_id FOREIGN KEY (user_id) REFERENCES public.auth_user(id) DEFERRABLE INITIALLY DEFERRED;
 l   ALTER TABLE ONLY public.django_admin_log DROP CONSTRAINT django_admin_log_user_id_c564eba6_fk_auth_user_id;
       public               postgres    false    243    4981    249            �           2606    26363 N   fee_households fee_households_household_id_6466fcbf_fk_households_household_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.fee_households
    ADD CONSTRAINT fee_households_household_id_6466fcbf_fk_households_household_id FOREIGN KEY (household_id) REFERENCES public.households(household_id) DEFERRABLE INITIALLY DEFERRED;
 x   ALTER TABLE ONLY public.fee_households DROP CONSTRAINT fee_households_household_id_6466fcbf_fk_households_household_id;
       public               postgres    false    259    221    4944            �           2606    25963    fees fees_created_by_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.fees
    ADD CONSTRAINT fees_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(user_id);
 C   ALTER TABLE ONLY public.fees DROP CONSTRAINT fees_created_by_fkey;
       public               postgres    false    4955    224    218            �           2606    26517 +   fee_households fk_feehouseholds_fee_cascade    FK CONSTRAINT     �   ALTER TABLE ONLY public.fee_households
    ADD CONSTRAINT fk_feehouseholds_fee_cascade FOREIGN KEY (fee_id) REFERENCES public.fees(fee_id) ON DELETE CASCADE;
 U   ALTER TABLE ONLY public.fee_households DROP CONSTRAINT fk_feehouseholds_fee_cascade;
       public               postgres    false    4931    259    218            �           2606    25968 4   household_changes household_changes_approved_by_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.household_changes
    ADD CONSTRAINT household_changes_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.users(user_id);
 ^   ALTER TABLE ONLY public.household_changes DROP CONSTRAINT household_changes_approved_by_fkey;
       public               postgres    false    224    4955    219            �           2606    26320 F   household_changes household_changes_household_id_3c48b520_fk_household    FK CONSTRAINT     �   ALTER TABLE ONLY public.household_changes
    ADD CONSTRAINT household_changes_household_id_3c48b520_fk_household FOREIGN KEY (household_id) REFERENCES public.households(household_id) DEFERRABLE INITIALLY DEFERRED;
 p   ALTER TABLE ONLY public.household_changes DROP CONSTRAINT household_changes_household_id_3c48b520_fk_household;
       public               postgres    false    219    221    4944            �           2606    25978 5   household_changes household_changes_requested_by_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.household_changes
    ADD CONSTRAINT household_changes_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(user_id);
 _   ALTER TABLE ONLY public.household_changes DROP CONSTRAINT household_changes_requested_by_fkey;
       public               postgres    false    224    219    4955            �           2606    25983 5   household_members household_members_household_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.household_members
    ADD CONSTRAINT household_members_household_id_fkey FOREIGN KEY (household_id) REFERENCES public.households(household_id) ON UPDATE CASCADE ON DELETE CASCADE;
 _   ALTER TABLE ONLY public.household_members DROP CONSTRAINT household_members_household_id_fkey;
       public               postgres    false    4944    221    220            �           2606    25988 "   households households_head_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.households
    ADD CONSTRAINT households_head_id_fkey FOREIGN KEY (head_id) REFERENCES public.users(user_id);
 L   ALTER TABLE ONLY public.households DROP CONSTRAINT households_head_id_fkey;
       public               postgres    false    224    221    4955            �           2606    26502    payments payments_fee_id_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_fee_id_fkey FOREIGN KEY (fee_id) REFERENCES public.fees(fee_id) ON DELETE CASCADE;
 G   ALTER TABLE ONLY public.payments DROP CONSTRAINT payments_fee_id_fkey;
       public               postgres    false    4931    222    218            �           2606    26330 B   payments payments_household_id_541294a5_fk_households_household_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_household_id_541294a5_fk_households_household_id FOREIGN KEY (household_id) REFERENCES public.households(household_id) DEFERRABLE INITIALLY DEFERRED;
 l   ALTER TABLE ONLY public.payments DROP CONSTRAINT payments_household_id_541294a5_fk_households_household_id;
       public               postgres    false    4944    221    222            �           2606    26335 G   residency_requests residency_requests_user_id_f051920d_fk_users_user_id    FK CONSTRAINT     �   ALTER TABLE ONLY public.residency_requests
    ADD CONSTRAINT residency_requests_user_id_f051920d_fk_users_user_id FOREIGN KEY (user_id) REFERENCES public.users(user_id) DEFERRABLE INITIALLY DEFERRED;
 q   ALTER TABLE ONLY public.residency_requests DROP CONSTRAINT residency_requests_user_id_f051920d_fk_users_user_id;
       public               postgres    false    223    4955    224            x      x������ � �      z      x������ � �      v     x�m��n�0E�����p�@x�ߨTQ�$Hh���5�}'�[�9#�;�QCu���:�*7<��2ʯ?����&�x>''���AK`��!����������{#Cm2���v���8����ޢ� ���	����� ��}�<M��,	ҷ6��u�bĠSDX��:�D�,�l��sv�jH���M��s��@��3��`���2��t�q��V=^w�Z2���6�,`��<�!_o��&]��d��9�%Y��k��Pc7*�t�2�P2�t2�r�ϣ���x�Վ�Mk]� #���#�>�B�$7��2C]ΐݬ2ԉY��P'2d�E�:Ȑ�뻩n��幽����mS��ܴ����o-�-//�mW���Mƞ<���棧�[@/WXj+&��jENLp��b��	 *�V��ɟ�|��p|��率=�T�}݈�(���ULL��ź���H?l�V�4VW��q
ۺ)�t-��S��@���LB�LTl�:��Ȅ5�ԭT��?qb^�c����Ev�������B��      |   �   x�-�A�0��������u�M2��CFa�M�&�����s�_~@��gY�M?r�FH��"_K��[5�����?��}�)���x4����dfwat��k0�(Mh�zՁ�A�ܧp,f󘋀s	Rx4"#Qe߼!�`�U�pY���b��c��G9����d��\�q~�4�      ~      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �   �   x�u�-N�@ `==�d-yͼy?ө��:@L;킩�n�hA8A-�$�=zhB$�]�C�p
N,r�X3��_�`zI��AE��L1�=H+��(E�`�u~���:?��q���m<47�]ʹϻ�O�;S,�߇�}��"%Ff��K���~ E�3�I"�
����m4�eZ���oy�Οv��/ݙ���k�RI���Nz$eȡJ��3$�pa��!�`g.��^}}�[��pf�-����~^�      t   �   x�]�K� D��0UI��K7$���n_T����fd���]P[\2W�)٪�N��@c7+ǒ�ҡ��j�!�Z�	�tk�Po�����ul�zt�O<�������M�֝���2>҂�00[V��`_~�ND�luQF      r   '  x���ݎ�0���)�?Y��y��4=R�	P��f}��V�$�^��7�o�@u��d�i�v�B�]�&g�
#�>��|�f�F�$�"�������}`��R��s����L
�B�#�֟c�᪃����1�צi��pF��<1L���|�O�9��Żc���
xb�'[�^̲�ӊ�Mg�Q���	%�>�M;٠:7����;�[۟�[�(�%e	%�,�y��׾�0$ �S
]S�%���Ƒ̅ *�f�f��zw6�/z�	�u �r?g�ݬ]'g/\��txL�X*�2�k��Ø�oC�Awv��U����#'7弳,9%�I��ԓ�_�T4u���(@��<�
C ʧx�������!���j ��$���)�x������d>c �!��W���&U��{���z2�Z��_|,������ot�b�dQ#RS�d�h�#�
��a�;y�ʿ������k62�=��e�@1�\�P2���$?f`�B1�F��q[�JR�):���&+�IgI<�[7�S�u�/{��X�فc�Pn���n���Ԅ      �     x���ɮ�H��u�S�e+#`gl�1�m�X-Y���O��Y��U�ZWI-�Bb���9�T�7�=Q�Y<��73�#��#�|~ۆ���A<L��2NHG�n�`�z��]�}<�| �pxW�3�c}^��W�gVwO��{�苨Zfs��m��	$'Xu@�EpE #�PedG�,����W��ul�)+=^J+I,:��hx`���#!UK�z�o.��ȸѣXa͉ԕW1���h:�z�<�Nc���m�X��x���H�������Y{��)>>���
7�Pg��XɎ($<��i�<1(/|�M��D��c�=Pѥ�"��r�/����1��nq�~���H@2�n�'��4�S̖e ���b���"L�)��%`�Wy�C�|�b�i�͔TV0}!/�!��y=k���AK��5���Mk>����A���r_�U���nGͼ=�E����Y�,��Y�|�@�:V�^��o�X�~�m4$Xa\�*:�t�^Mtr+�v�b��`��â����r�mi�_+���w��}��w���/U���"�O��i��@
��Gd&H�4 c��#�҉*܊�&��B�e��_�9�^T_��,�:�" &K����d�����Y�G:
����[�F�$>Gb\,�;e���ʡ�.�>苚��%��B�C��ͭ�:~�sF�on�L�ۆ~�__g
&�H�.ΟD� ��-�hDr����J�^��^�:Lq��D�p�����Lx���w�M�����B���=2�v�#6G]����݅����4ۅW�.�ҹ��I�l��kKʾ���M�l�Jq${�N7'^��iQN)�ȞN��N�<AU.�G��݃��iB�^#�bmv(��l6/{}��d����h��ӈ��<���[��I@�<�j����MD��)�4�9���&�[���M����&�|�x�\�0���ύ0]���%�<�K���u?�m���?��$O#�b�`�_I�Y�z��uu9faρ�z�->;�)��a�ʵ|�$�/��ՍO�T����=��\��♤�jZ�lEw�����Mr<����`?Y��tG��}�0#�
��E@}�j�o)�+���)� ���1P�#����L��,RʥKY��[ �$ O���"(���
Y�BȖ�V"��|l\bf��p���W�*^�u�WT��U��;�`��jf����S1�f����<�V{?:����]o!Qu�Ps�����(��8C���D������.F��v.�[`h:ֺ4)�[��1��Kφ_��ML�S�8���V[775��0�"��\�olo���g�A��K��S/t�՞e�t=$�.7�����.A<�n�����Nا�����9����l���˪�w�$E@���K\������I�vl|q��zD���]�A����EDQdU _�y5T�f�0��6�n8;���Ge�I)���#~t?g�w�8m�U[3N�>O�2]Kơ�.0���X����e�S�}/5�:K7�M+%��NaG�k5�
w,�'~��'�,�-"���o�����I      �   �   x��ѻ�@!���{�#B/�h�%�ہ��^g G��$'Tt�I\��6���t'J�q uOK�tVFh�#��v�L7B$�}3��zi]l�N�f}��_-R0�>�_�e4�Y���t�i�RL��10�����ao5�{�I���&��@bu0	��A:m~KF؆f��۞7YW�	�O��S��͌�{KƏ��̤	m��h��࿋�����=�+߰ߟ��� #��O      j   P  x���=j�@�Z�{��3�_:E�f?-����&.S�.S�"�C ��R&��M2ƅ�)�@�+�����V��$=� ɥ&� ]B��f���ތ�(��1��j����{�%�w�ם6�W�F*+t`�M���1{IT�L�Hf���i�r������7A��n�Ac���dI�U�@����4��z��Yu�L��b~���P�F�y%�
etB�I绶Q���*J��I�`��de&lN1���W�n��^g�R��T~P�G�� �����Y3�$�s������ل*u��}{"�e�,�'~.ӗS��]�]��.���:X�>J�=���"���j�����3�
�/���I?gv��E�#C��ͮ'�(_�W�kǰ�K�@B���o@����E�x{�9]��b��_i���Q4 {�4p����c(�אy��\r2�RyY�O[q>��n/��Ͽz�K�Pv ?h�;�2�i�ci�2)&�����g�tZ56Ft�0�4��.o�mh���2�'�{3
��ܔ�6	*T��
���5�٪��Cҡ�՘-�q���ݎ��j����@�+S���qjo��f�&���      k      x������ � �      l   p  x���MkW���_q�o���X$q�-Z*B��OK��ͺ�.J !�,
VK�-�(�]�����s%��+�@1:3��g��=�3��'�J�a�Q%�0�+m*nT
Tx���XD���XXA���Hj��A{��F��~�ѽj�}�����ZK0���j0l��!z2l'��fs����ͨ���=��F��l������F���j'����'�VRƅ��ڊ
+*Le�k>Ի�՝����כ*��1�d�&r-i
�PXx(�2xoI�2��Pl7�� ��mT��'���(���>z6j�׷[����BՅ�54��߯p�����h� r�>'��R�S-�w��F3F�E��@�)�2��v�"����m�3A�2.ּ�Bo���$i��`�<<l<����Y�d+�r�Vp�D���>0���,:e�����=o'?��*n#�H�J����m������ ����гb�'���z�s���2�&E�w3	w��fID���Z��M\��r\�I�aq�F�2vG���zP ���N��ƠxH/�&p�#��R�Ab�1%�5Q�̃�w��x-srG WqS9�����gYS0�6�?K��gY�2X-�tΐXi�M`"�.ć��̸a�KI�հ=����u޿6��V��8S�+��F���O�ɯ��:�M1���Z�H�T��h���Jc��Y����oq�����NI�"�]T�m6��O(q���6�	��bBL}
a��i����g�!��J��D�Y��F������9�qTep(@b%+&AhO�d9��'�cXuZ@�
V����x�J��$<�˥�u�X2�1�&�en)�� �DuW$�����rU�8���5v�C���<�
�Çh(vR8�GsH)i �Ei/��4zz�arE4G���x�[�N�6�!�e7���W���/qQ���!57���U��<��9"Z����`����S�,�JŪ����� Z��~A47SN8G�!����'0;�N�Y^B�;j��è�ٌ��0k�p�p�&���.�����3�u9����bх�[2�,v��u���s"��t9"��X[[��PkV      m   �  x�}�;n1�ڳ���ݷ��B��(i�$I�f�����$;�B!��Wrq>��z��'�b��19�j7�����pG(aj"��!5��
�u��$���9Hx������]����?�w���mg>YO���D�/9QN�C�y�^�sPZ_a�j��dI<�aǋš�T���Ǆ�{�X�E�����7X�n�Hv�S�D>2�Hy�䣑V�9-V_WQ��YQ\(�����s0�:/�Zݣ!fݯ��/ګ?id����:"��l���2���C�fR`��V����i(^\����#(��Xr��T��(��_��p��~������S��|d���R�;���&c��U����Am��W�^<w�?���)�71�u��,	
���{�_�`��}э���RI:�Lm{wl���R�v      n   �  x���[n#GE��Ux�HV��Z�D���n;��r2�nAZ����%eI�+dc��BnS�2,z��mܤTsF�� Uc�-�:�Ա<K���+B���q���;~Sx��N�q�B��zM�!��窹��h�t������%���é4^�cf
�Ҫ%�Z}͡��y��F��&m\ɥW*��D˧����]����F�ڍR�L�dP�4�����*��x-Ak0�2�m�UW�Qbp꟢��{Il�OT��D�2��iؕ��E���l�[�sT>���GkE�9�M�䑌g��Ti�:�%�e�	q��F�+��{k^o�����7�� �"^�@��E���Q�#�'��Ftq��J��{���*Uڎ��8�JW^����_~��u{�Qc�hG�4|R�7��3��li��A��ӎ�g�]ӊ���=��G�����("�ΝQI��>
�yʪQJ=� TXjĢ6&`���b�8�^�La�_Ɂ��i�S؀vl(�$���4O���sU;��e~���(�ڜ�a�  ����%*1nȄ@	�E�w�4�i������)�狕zk/e\wO����,9L�H��f����.3֓T׭�Tk��!�貣�}�c�%_����'��T{ga�Nu`f��:z���=-#��xζ/�ZU<ˉ����y�G����ae2{�x��Ft���kztp�ݔ&/���M�땵�5h��[��{�I�75�Y�H�}^t�,��D9�ϝ����w}h`��B�CȄ��s�a���$��P��h`�Ǫ~��!%ԩ�@�b�s���S����v����k�JF��b�\T�noW��w��>��s����
�)F�&�����
���9�4���B��mi�X\��L��հ��u&{0.��H�	���Q�_�]0Z�>�5��rKm�Z���1�c	���
�Ujkb뺘�pS��'1Őni/J��
������ŀ�{�}��r���������	=�*��8,;�J���$��P��'L������J�g_إ��5���uQ}��Xl���'x��h�Z���ݔ��*�B@��U���E���3����t/�S�S8U��;6Ԏ{�X[�����sS�&�)��[����n�z9�8�_��)/�������©���;;������2:�(      o   w  x���A�1EשS�\�'NՎ��lf�	��3t5�͠9G�4܄��Z�M��%[��)��E �$�VE��*V�1�0� 2��%j B�ѝ��ú���ަc���9 F ��Th�ݸW��������Gg�ö>�rư#��0�|T���#�H�'��ZU(̒��@�B%z.�M}��Og�����鸘�����o�v�@�c?J����C��b�:���s;I;?'�"�p�T�P�5�Q0�_���r�ќ�sIѽ]���Vw���=Z�Ӳ��V?�|�&�Q���ѧk�=�5u�"�B��[S[&�%�K�n�_J�S8�\�@���?�hJ����s�C��%E�����]�u�/�      p   �  x���;o�6����R!)>�l~�v����(pAR�#�e[�d;kѩs��C�.]tj<tH���oR����vI����&�F:[�f@�1̅cbs�2��e��z�.����U�qj��ξԫ��R�Y�<�lk��`aK�y�0�sRI�g��uV��Tnx<�PF�O��ϡW@9�� �91�H_!zE�A)G��!oB�jm;�ނ�p���l,Ű�@�l��^������O���H��U�@y�ѷv9��M��r/^�a����:'|���#n����@eB	�)	PT�H"	�����"�'�ϭ��|�i��=m��}�)L��~i�o���U
�*.�U��xh��� ����>�8>�Q._Ï���������m�����XN%��YD�����_�NR��Ȳ�ʰ�wrV߯����D�w�z 't9�����oqG��_����o�B��lGZ�����*��a;pI�.g�����i�*w��Vi&w}:]�~w�4C�����ިy�sG����_wֆ�3��%��Ự0���nY�)�W�U\a��*{'�D���<�aK�v�=�%b_���Y/��$����l?j�pY���S,��Y���Ϗ�S����]b!ʴ� ����.�L�q\"9>�ə�hs���]��h��Eu�'�~�J��]#X�&��N�F��X�l�qf7_�^�a�
B�0|�[0�L+k�"HAm�E\b:�>��٭�%�6�o��~dMk���
����hy#��h��j�>O�t���u<�^h?�/� �ȯ2+E_�3�TQ��,e�[�l�gy[.�ܥ���"���l�g�Y�֋]��%1�A5���l��"wݨ}��Eq0*��K�[7��Uyˢ�߉�_�
��_�7�O�׽ľ���L������Z`ߍ     