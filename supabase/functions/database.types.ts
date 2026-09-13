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
      clinical_events: {
        Row: {
          created_at: string;
          id: string;
          kind: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at: string;
          patient_id: string;
          payload: Json;
          recorded_by: string | null;
        };
        Insert: {
          created_at?: string;
          id?: string;
          kind: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at: string;
          patient_id: string;
          payload?: Json;
          recorded_by?: string | null;
        };
        Update: {
          created_at?: string;
          id?: string;
          kind?: Database["public"]["Enums"]["clinical_event_kind"];
          occurred_at?: string;
          patient_id?: string;
          payload?: Json;
          recorded_by?: string | null;
        };
        Relationships: [
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
          payload?: Json;
          rut?: string | null;
          updated_at?: string;
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
    };
    Views: {
      [_ in never]: never;
    };
    Functions: {
      can_read_clinical_events: { Args: never; Returns: boolean };
      can_read_patients: { Args: never; Returns: boolean };
      is_administrator: { Args: never; Returns: boolean };
      normalize_rut: { Args: { value: string }; Returns: string };
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
