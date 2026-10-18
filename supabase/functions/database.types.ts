export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  public: {
    Tables: {
      audit_events: {
        Row: {
          action: string;
          actor_auth_user_id: string | null;
          actor_membership_id: string | null;
          id: string;
          idempotency_key: string;
          metadata: Json;
          occurred_at: string;
          organization_id: string;
          result: string;
          target_id: string | null;
          target_type: string;
        };
        Insert: {
          action: string;
          actor_auth_user_id?: string | null;
          actor_membership_id?: string | null;
          id?: string;
          idempotency_key: string;
          metadata?: Json;
          occurred_at?: string;
          organization_id: string;
          result: string;
          target_id?: string | null;
          target_type: string;
        };
        Update: {
          action?: string;
          actor_auth_user_id?: string | null;
          actor_membership_id?: string | null;
          id?: string;
          idempotency_key?: string;
          metadata?: Json;
          occurred_at?: string;
          organization_id?: string;
          result?: string;
          target_id?: string | null;
          target_type?: string;
        };
        Relationships: [
          {
            foreignKeyName: "audit_events_actor_membership_fk";
            columns: ["organization_id", "actor_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "audit_events_actor_membership_fk";
            columns: ["organization_id", "actor_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "audit_events_actor_membership_fk";
            columns: ["organization_id", "actor_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "audit_events_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "audit_events_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      care_assignments: {
        Row: {
          created_at: string;
          created_by_membership_id: string;
          hospitalization_id: string;
          id: string;
          membership_id: string;
          organization_id: string;
          relationship_code: string | null;
          revoked_at: string | null;
          revoked_by_membership_id: string | null;
          valid_from: string;
          valid_until: string | null;
        };
        Insert: {
          created_at?: string;
          created_by_membership_id: string;
          hospitalization_id: string;
          id?: string;
          membership_id: string;
          organization_id: string;
          relationship_code?: string | null;
          revoked_at?: string | null;
          revoked_by_membership_id?: string | null;
          valid_from: string;
          valid_until?: string | null;
        };
        Update: {
          created_at?: string;
          created_by_membership_id?: string;
          hospitalization_id?: string;
          id?: string;
          membership_id?: string;
          organization_id?: string;
          relationship_code?: string | null;
          revoked_at?: string | null;
          revoked_by_membership_id?: string | null;
          valid_from?: string;
          valid_until?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "care_assignments_creator_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_creator_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_creator_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "care_assignments_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "clinical_census_by_hospitalization";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "care_assignments_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation:
              "clinical_patient_demographics_by_hospitalization";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "care_assignments_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "hospitalizations";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "care_assignments_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_hospitalizations";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "care_assignments_membership_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_membership_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_membership_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "care_assignments_revoker_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_revoker_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "care_assignments_revoker_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      clinical_events: {
        Row: {
          created_at: string;
          hospitalization_id: string | null;
          id: string;
          kind: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at: string;
          organization_id: string | null;
          patient_id: string;
          payload: Json;
          recorded_by: string | null;
          summary: string;
        };
        Insert: {
          created_at?: string;
          hospitalization_id?: string | null;
          id?: string;
          kind: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at: string;
          organization_id?: string | null;
          patient_id: string;
          payload?: Json;
          recorded_by?: string | null;
          summary: string;
        };
        Update: {
          created_at?: string;
          hospitalization_id?: string | null;
          id?: string;
          kind?: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at?: string;
          organization_id?: string | null;
          patient_id?: string;
          payload?: Json;
          recorded_by?: string | null;
          summary?: string;
        };
        Relationships: [
          {
            foreignKeyName: "clinical_events_episode_patient_tenant_fk";
            columns: ["organization_id", "hospitalization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "clinical_census_by_hospitalization";
            referencedColumns: [
              "organization_id",
              "hospitalization_id",
              "patient_id",
            ];
          },
          {
            foreignKeyName: "clinical_events_episode_patient_tenant_fk";
            columns: ["organization_id", "hospitalization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "hospitalizations";
            referencedColumns: ["organization_id", "id", "patient_id"];
          },
          {
            foreignKeyName: "clinical_events_patient_id_fkey";
            columns: ["patient_id"];
            isOneToOne: false;
            referencedRelation:
              "clinical_patient_demographics_by_hospitalization";
            referencedColumns: ["patient_id"];
          },
          {
            foreignKeyName: "clinical_events_patient_id_fkey";
            columns: ["patient_id"];
            isOneToOne: false;
            referencedRelation: "patients";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "clinical_events_recorded_by_fkey";
            columns: ["recorded_by"];
            isOneToOne: false;
            referencedRelation: "practitioners";
            referencedColumns: ["id"];
          },
        ];
      };
      context_notes: {
        Row: {
          author_id: string;
          client_event_id: string;
          confirmed_at: string;
          content: string | null;
          created_at: string;
          hospitalization_id: string;
          id: string;
          input_method: string;
          occurred_at: string;
          organization_id: string;
          patient_id: string;
          status: string;
          transcription_metadata: Json | null;
        };
        Insert: {
          author_id?: string;
          client_event_id: string;
          confirmed_at?: string;
          content?: string | null;
          created_at?: string;
          hospitalization_id: string;
          id?: string;
          input_method: string;
          occurred_at?: string;
          organization_id: string;
          patient_id: string;
          status?: string;
          transcription_metadata?: Json | null;
        };
        Update: {
          author_id?: string;
          client_event_id?: string;
          confirmed_at?: string;
          content?: string | null;
          created_at?: string;
          hospitalization_id?: string;
          id?: string;
          input_method?: string;
          occurred_at?: string;
          organization_id?: string;
          patient_id?: string;
          status?: string;
          transcription_metadata?: Json | null;
        };
        Relationships: [
          {
            foreignKeyName: "context_notes_episode_patient_tenant_fk";
            columns: ["organization_id", "hospitalization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "clinical_census_by_hospitalization";
            referencedColumns: [
              "organization_id",
              "hospitalization_id",
              "patient_id",
            ];
          },
          {
            foreignKeyName: "context_notes_episode_patient_tenant_fk";
            columns: ["organization_id", "hospitalization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "hospitalizations";
            referencedColumns: ["organization_id", "id", "patient_id"];
          },
          {
            foreignKeyName: "context_notes_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "context_notes_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      hospitalization_locations: {
        Row: {
          bed_label: string | null;
          created_at: string;
          ended_at: string | null;
          hospitalization_id: string;
          id: string;
          organization_id: string;
          started_at: string;
          unit_id: string | null;
        };
        Insert: {
          bed_label?: string | null;
          created_at?: string;
          ended_at?: string | null;
          hospitalization_id: string;
          id?: string;
          organization_id: string;
          started_at: string;
          unit_id?: string | null;
        };
        Update: {
          bed_label?: string | null;
          created_at?: string;
          ended_at?: string | null;
          hospitalization_id?: string;
          id?: string;
          organization_id?: string;
          started_at?: string;
          unit_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "hospitalization_locations_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "clinical_census_by_hospitalization";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "hospitalization_locations_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation:
              "clinical_patient_demographics_by_hospitalization";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "hospitalization_locations_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "hospitalizations";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "hospitalization_locations_episode_fk";
            columns: ["organization_id", "hospitalization_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_hospitalizations";
            referencedColumns: ["organization_id", "hospitalization_id"];
          },
          {
            foreignKeyName: "hospitalization_locations_unit_fk";
            columns: ["organization_id", "unit_id"];
            isOneToOne: false;
            referencedRelation: "units";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      hospitalizations: {
        Row: {
          admitted_at: string;
          created_at: string;
          discharged_at: string | null;
          id: string;
          organization_id: string;
          patient_id: string;
          status: string;
        };
        Insert: {
          admitted_at: string;
          created_at?: string;
          discharged_at?: string | null;
          id?: string;
          organization_id: string;
          patient_id: string;
          status: string;
        };
        Update: {
          admitted_at?: string;
          created_at?: string;
          discharged_at?: string | null;
          id?: string;
          organization_id?: string;
          patient_id?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "hospitalizations_patient_tenant_fk";
            columns: ["organization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "patients";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      organization_memberships: {
        Row: {
          created_at: string;
          id: string;
          local_identifier: string | null;
          organization_id: string;
          profile_id: string;
          status: string;
          updated_at: string;
          valid_from: string;
          valid_until: string | null;
        };
        Insert: {
          created_at?: string;
          id?: string;
          local_identifier?: string | null;
          organization_id: string;
          profile_id: string;
          status?: string;
          updated_at?: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Update: {
          created_at?: string;
          id?: string;
          local_identifier?: string | null;
          organization_id?: string;
          profile_id?: string;
          status?: string;
          updated_at?: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "organization_memberships_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "organization_memberships_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["profile_id"];
          },
          {
            foreignKeyName: "organization_memberships_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      organizations: {
        Row: {
          created_at: string;
          display_name: string;
          id: string;
          slug: string;
          status: string;
          timezone: string;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          display_name: string;
          id?: string;
          slug: string;
          status?: string;
          timezone?: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          display_name?: string;
          id?: string;
          slug?: string;
          status?: string;
          timezone?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      patients: {
        Row: {
          bed_label: string | null;
          birth_date: string | null;
          care_unit: string | null;
          created_at: string;
          external_reference: string | null;
          family_name: string;
          given_name: string;
          id: string;
          organization_id: string | null;
          payload: Json;
          rut: string | null;
          updated_at: string;
        };
        Insert: {
          bed_label?: string | null;
          birth_date?: string | null;
          care_unit?: string | null;
          created_at?: string;
          external_reference?: string | null;
          family_name: string;
          given_name: string;
          id?: string;
          organization_id?: string | null;
          payload?: Json;
          rut?: string | null;
          updated_at?: string;
        };
        Update: {
          bed_label?: string | null;
          birth_date?: string | null;
          care_unit?: string | null;
          created_at?: string;
          external_reference?: string | null;
          family_name?: string;
          given_name?: string;
          id?: string;
          organization_id?: string | null;
          payload?: Json;
          rut?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "patients_organization_fk";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "patients_organization_fk";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      permission_catalog: {
        Row: {
          code: string;
          delegation_policy: string;
          deprecated_at: string | null;
          description: string;
          family: string;
          introduced_at: string;
          status: string;
        };
        Insert: {
          code: string;
          delegation_policy?: string;
          deprecated_at?: string | null;
          description: string;
          family: string;
          introduced_at?: string;
          status?: string;
        };
        Update: {
          code?: string;
          delegation_policy?: string;
          deprecated_at?: string | null;
          description?: string;
          family?: string;
          introduced_at?: string;
          status?: string;
        };
        Relationships: [];
      };
      practitioners: {
        Row: {
          created_at: string;
          display_name: string;
          id: string;
          license_number: string | null;
          role: Database["public"]["Enums"]["practitioner_role"];
          status: Database["public"]["Enums"]["practitioner_status"];
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          display_name: string;
          id: string;
          license_number?: string | null;
          role: Database["public"]["Enums"]["practitioner_role"];
          status?: Database["public"]["Enums"]["practitioner_status"];
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          display_name?: string;
          id?: string;
          license_number?: string | null;
          role?: Database["public"]["Enums"]["practitioner_role"];
          status?: Database["public"]["Enums"]["practitioner_status"];
          updated_at?: string;
        };
        Relationships: [];
      };
      profiles: {
        Row: {
          auth_user_id: string;
          created_at: string;
          display_name: string;
          id: string;
          status: string;
          updated_at: string;
        };
        Insert: {
          auth_user_id: string;
          created_at?: string;
          display_name: string;
          id?: string;
          status?: string;
          updated_at?: string;
        };
        Update: {
          auth_user_id?: string;
          created_at?: string;
          display_name?: string;
          id?: string;
          status?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      role_assignments: {
        Row: {
          created_at: string;
          created_by_membership_id: string | null;
          id: string;
          membership_id: string;
          organization_id: string;
          revoked_at: string | null;
          revoked_by_membership_id: string | null;
          role_id: string;
          scope_type: string;
          valid_from: string;
          valid_until: string | null;
        };
        Insert: {
          created_at?: string;
          created_by_membership_id?: string | null;
          id?: string;
          membership_id: string;
          organization_id: string;
          revoked_at?: string | null;
          revoked_by_membership_id?: string | null;
          role_id: string;
          scope_type?: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Update: {
          created_at?: string;
          created_by_membership_id?: string | null;
          id?: string;
          membership_id?: string;
          organization_id?: string;
          revoked_at?: string | null;
          revoked_by_membership_id?: string | null;
          role_id?: string;
          scope_type?: string;
          valid_from?: string;
          valid_until?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "role_assignments_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "role_assignments_revoked_by_membership_tenant_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_revoked_by_membership_tenant_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_revoked_by_membership_tenant_fk";
            columns: ["organization_id", "revoked_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "role_assignments_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "iam_role_directory";
            referencedColumns: ["organization_id", "role_id"];
          },
          {
            foreignKeyName: "role_assignments_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      role_permissions: {
        Row: {
          granted_at: string;
          granted_by_membership_id: string | null;
          organization_id: string;
          permission_code: string;
          role_id: string;
        };
        Insert: {
          granted_at?: string;
          granted_by_membership_id?: string | null;
          organization_id: string;
          permission_code: string;
          role_id: string;
        };
        Update: {
          granted_at?: string;
          granted_by_membership_id?: string | null;
          organization_id?: string;
          permission_code?: string;
          role_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "role_permissions_granted_by_membership_tenant_fk";
            columns: ["organization_id", "granted_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_permissions_granted_by_membership_tenant_fk";
            columns: ["organization_id", "granted_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_permissions_granted_by_membership_tenant_fk";
            columns: ["organization_id", "granted_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "role_permissions_permission_code_fkey";
            columns: ["permission_code"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["permission_code"];
          },
          {
            foreignKeyName: "role_permissions_permission_code_fkey";
            columns: ["permission_code"];
            isOneToOne: false;
            referencedRelation: "iam_role_directory";
            referencedColumns: ["permission_code"];
          },
          {
            foreignKeyName: "role_permissions_permission_code_fkey";
            columns: ["permission_code"];
            isOneToOne: false;
            referencedRelation: "permission_catalog";
            referencedColumns: ["code"];
          },
          {
            foreignKeyName: "role_permissions_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "iam_role_directory";
            referencedColumns: ["organization_id", "role_id"];
          },
          {
            foreignKeyName: "role_permissions_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      roles: {
        Row: {
          created_at: string;
          created_by_membership_id: string | null;
          description: string;
          id: string;
          is_system: boolean;
          name: string;
          organization_id: string;
          protected_kind: string | null;
          status: string;
          updated_at: string;
        };
        Insert: {
          created_at?: string;
          created_by_membership_id?: string | null;
          description: string;
          id?: string;
          is_system?: boolean;
          name: string;
          organization_id: string;
          protected_kind?: string | null;
          status?: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          created_by_membership_id?: string | null;
          description?: string;
          id?: string;
          is_system?: boolean;
          name?: string;
          organization_id?: string;
          protected_kind?: string | null;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "roles_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "roles_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "roles_created_by_membership_tenant_fk";
            columns: ["organization_id", "created_by_membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      units: {
        Row: {
          code: string;
          created_at: string;
          display_name: string;
          id: string;
          organization_id: string;
          status: string;
        };
        Insert: {
          code: string;
          created_at?: string;
          display_name: string;
          id?: string;
          organization_id: string;
          status?: string;
        };
        Update: {
          code?: string;
          created_at?: string;
          display_name?: string;
          id?: string;
          organization_id?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "units_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "units_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      clinical_census_by_hospitalization: {
        Row: {
          admitted_at: string | null;
          bed_label: string | null;
          birth_date: string | null;
          discharged_at: string | null;
          family_name: string | null;
          given_name: string | null;
          hospitalization_id: string | null;
          hospitalization_status: string | null;
          organization_id: string | null;
          patient_id: string | null;
          unit_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "hospitalizations_patient_tenant_fk";
            columns: ["organization_id", "patient_id"];
            isOneToOne: false;
            referencedRelation: "patients";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      clinical_patient_demographics_by_hospitalization: {
        Row: {
          birth_date: string | null;
          family_name: string | null;
          given_name: string | null;
          hospitalization_id: string | null;
          organization_id: string | null;
          patient_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      clinical_timeline_by_hospitalization: {
        Row: {
          created_at: string | null;
          event_id: string | null;
          hospitalization_id: string | null;
          kind: string | null;
          occurred_at: string | null;
          organization_id: string | null;
          patient_id: string | null;
          source_kind: string | null;
          summary: string | null;
        };
        Relationships: [];
      };
      iam_assignment_eligible_members: {
        Row: {
          display_name: string | null;
          membership_id: string | null;
          organization_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      iam_assignment_hospitalizations: {
        Row: {
          admitted_at: string | null;
          assignee_display_name: string | null;
          assignee_membership_status: string | null;
          assignment_id: string | null;
          assignment_valid_from: string | null;
          assignment_valid_until: string | null;
          discharged_at: string | null;
          hospitalization_id: string | null;
          hospitalization_status: string | null;
          membership_id: string | null;
          organization_id: string | null;
          revoked_at: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "hospitalizations_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      iam_current_context: {
        Row: {
          display_name: string | null;
          membership_id: string | null;
          membership_status: string | null;
          organization_id: string | null;
          organization_name: string | null;
          permission_code: string | null;
          profile_id: string | null;
          profile_status: string | null;
        };
        Relationships: [];
      };
      iam_member_directory: {
        Row: {
          display_name: string | null;
          membership_id: string | null;
          membership_status: string | null;
          organization_id: string | null;
          profile_id: string | null;
          profile_status: string | null;
          valid_from: string | null;
          valid_until: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "organization_memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      iam_member_role_assignments: {
        Row: {
          assignment_id: string | null;
          membership_id: string | null;
          organization_id: string | null;
          protected_kind: string | null;
          revoked_at: string | null;
          role_id: string | null;
          role_name: string | null;
          valid_from: string | null;
          valid_until: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_assignment_eligible_members";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "iam_member_directory";
            referencedColumns: ["organization_id", "membership_id"];
          },
          {
            foreignKeyName: "role_assignments_membership_tenant_fk";
            columns: ["organization_id", "membership_id"];
            isOneToOne: false;
            referencedRelation: "organization_memberships";
            referencedColumns: ["organization_id", "id"];
          },
          {
            foreignKeyName: "role_assignments_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "iam_role_directory";
            referencedColumns: ["organization_id", "role_id"];
          },
          {
            foreignKeyName: "role_assignments_role_tenant_fk";
            columns: ["organization_id", "role_id"];
            isOneToOne: false;
            referencedRelation: "roles";
            referencedColumns: ["organization_id", "id"];
          },
        ];
      };
      iam_role_directory: {
        Row: {
          description: string | null;
          organization_id: string | null;
          permission_code: string | null;
          protected_kind: string | null;
          role_id: string | null;
          role_name: string | null;
          role_status: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "iam_current_context";
            referencedColumns: ["organization_id"];
          },
          {
            foreignKeyName: "roles_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Functions: {
      bootstrap_legacy_practitioner_iam: { Args: never; Returns: undefined };
      bootstrap_synthetic_hospitalization_fixtures: {
        Args: never;
        Returns: undefined;
      };
      context_note_publication_matches: {
        Args: {
          p_client_event_id: string;
          p_content: string;
          p_hospitalization_id: string;
          p_input_method: string;
          p_organization_id: string;
          p_patient_id: string;
          p_transcription_metadata: Json;
        };
        Returns: boolean;
      };
      create_iam_role: {
        Args: {
          p_description: string;
          p_idempotency_key: string;
          p_name: string;
          p_organization_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      deactivate_iam_role: {
        Args: {
          p_idempotency_key: string;
          p_organization_id: string;
          p_role_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      grant_care_assignment: {
        Args: {
          p_hospitalization_id: string;
          p_idempotency_key: string;
          p_membership_id: string;
          p_organization_id: string;
          p_valid_from: string;
          p_valid_until: string;
        };
        Returns: {
          assignment_id: string;
          replayed: boolean;
          result: boolean;
          result_code: string;
        }[];
      };
      grant_iam_administrator: {
        Args: {
          p_idempotency_key: string;
          p_membership_id: string;
          p_organization_id: string;
          p_role_id: string;
          p_valid_from: string;
          p_valid_until: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      grant_iam_role: {
        Args: {
          p_idempotency_key: string;
          p_membership_id: string;
          p_organization_id: string;
          p_role_id: string;
          p_valid_from: string;
          p_valid_until: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      has_active_iam_permission: {
        Args: { p_organization_id: string; p_permission_code: string };
        Returns: boolean;
      };
      has_active_organization_membership: {
        Args: { p_organization_id: string };
        Returns: boolean;
      };
      iam_current_profile_id: { Args: never; Returns: string };
      is_administrator: { Args: never; Returns: boolean };
      is_current_active_membership: {
        Args: { p_membership_id: string };
        Returns: boolean;
      };
      manage_organization_membership: {
        Args: {
          p_idempotency_key: string;
          p_membership_id: string;
          p_organization_id: string;
          p_status: string;
          p_valid_until: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      normalize_rut: { Args: { value: string }; Returns: string };
      preflight_organization_member_registration: {
        Args: {
          p_display_name: string;
          p_email: string;
          p_idempotency_key: string;
          p_organization_id: string;
          p_role_id: string;
        };
        Returns: {
          assignment_id: string;
          membership_id: string;
          profile_id: string;
          replayed: boolean;
          result_code: string;
        }[];
      };
      register_organization_member: {
        Args: {
          p_auth_user_id: string;
          p_display_name: string;
          p_email: string;
          p_idempotency_key: string;
          p_organization_id: string;
          p_role_id: string;
        };
        Returns: {
          assignment_id: string;
          membership_id: string;
          profile_id: string;
          replayed: boolean;
          result_code: string;
        }[];
      };
      replace_iam_role_permissions: {
        Args: {
          p_idempotency_key: string;
          p_organization_id: string;
          p_permissions: string[];
          p_role_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      revoke_care_assignment: {
        Args: {
          p_assignment_id: string;
          p_idempotency_key: string;
          p_organization_id: string;
        };
        Returns: {
          assignment_id: string;
          replayed: boolean;
          result: boolean;
          result_code: string;
        }[];
      };
      revoke_iam_administrator: {
        Args: {
          p_assignment_id: string;
          p_idempotency_key: string;
          p_organization_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      revoke_iam_role: {
        Args: {
          p_assignment_id: string;
          p_idempotency_key: string;
          p_organization_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
      update_iam_role: {
        Args: {
          p_description: string;
          p_idempotency_key: string;
          p_name: string;
          p_organization_id: string;
          p_role_id: string;
        };
        Returns: {
          replayed: boolean;
          result: boolean;
          result_code: string;
          target_id: string;
        }[];
      };
    };
    Enums: {
      clinical_event_kind:
        | "observation"
        | "encounter"
        | "condition"
        | "procedure"
        | "document";
      practitioner_role: "physician" | "nurse" | "technician" | "administrator";
      practitioner_status: "active" | "suspended";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema =
  DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof (
      & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
        "Tables"
      ]
      & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
        "Views"
      ]
    )
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? (
    & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    & DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Views"
    ]
  )[TableName] extends {
    Row: infer R;
  } ? R
  : never
  : DefaultSchemaTableNameOrOptions extends keyof (
    & DefaultSchema["Tables"]
    & DefaultSchema["Views"]
  ) ? (
      & DefaultSchema["Tables"]
      & DefaultSchema["Views"]
    )[DefaultSchemaTableNameOrOptions] extends {
      Row: infer R;
    } ? R
    : never
  : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
    "Tables"
  ][TableName] extends {
    Insert: infer I;
  } ? I
  : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Insert: infer I;
    } ? I
    : never
  : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
      "Tables"
    ]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]][
    "Tables"
  ][TableName] extends {
    Update: infer U;
  } ? U
  : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
      Update: infer U;
    } ? U
    : never
  : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]][
      "Enums"
    ]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][
    EnumName
  ]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
  : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  } ? keyof DatabaseWithoutInternals[
      PublicCompositeTypeNameOrOptions["schema"]
    ]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
} ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]][
    "CompositeTypes"
  ][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
  : never;

export const Constants = {
  public: {
    Enums: {
      clinical_event_kind: [
        "observation",
        "encounter",
        "condition",
        "procedure",
        "document",
      ],
      practitioner_role: ["physician", "nurse", "technician", "administrator"],
      practitioner_status: ["active", "suspended"],
    },
  },
} as const;
