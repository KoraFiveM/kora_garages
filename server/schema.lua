QBGaragesSchema = {
    {
        name = 'qbgarages_property_garages',
        columns = {
            { name = 'id', type = 'varchar(50)' },
            { name = 'provider', type = 'varchar(64)' },
            { name = 'definition', type = 'longtext' },
        },
        primary = { 'id' },
    },
}
